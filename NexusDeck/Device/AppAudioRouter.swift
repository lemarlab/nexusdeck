import Foundation
import CoreAudio
import AppKit

/// Per-app audio routing, done inside the NexusDeck audio driver: the driver knows which app each client of its
/// devices is, and moves the audio of a routed app to the chosen channel before the device mix (no capture,
/// no extra buffering). NexusDeck only sends it the table "bundleID=channel".
/// Apps must play on a NexusDeck device (normally System, the default output).
@MainActor
final class AppAudioRouter: ObservableObject {
    struct AudioApp: Identifiable, Hashable {
        var id: String { bundleID }
        let bundleID: String
        let name: String
        let icon: NSImage?
        var playing: Bool
    }

    /// Apps currently known to Core Audio (grouped by app, helpers included).
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var lastError: String?

    private let store: ProfileStore
    private var listenerInstalled = false
    private var refreshWork: DispatchWorkItem?
    private var sentTable: String?

    /// Channels an app can be routed to, with the driver's ring index.
    static let channels: [(MixerChannel, Int)] = [
        (.system, 3), (.game, 4), (.chat, 5), (.lineIn, 6), (.console, 7),
    ]
    private static let routeSelector: AudioObjectPropertySelector = 0x6E64_7274 // 'ndrt'
    private static let driverBundleID = "com.nexusdeck.lemarlab.AudioPlugIn"

    init(store: ProfileStore) { self.store = store }

    func start() {
        installListener()
        refresh()
    }

    func setRoute(_ bundleID: String, _ channel: String?) {
        store.library.appRoutes[bundleID] = channel
        sendTable()
    }

    /// Sends the routing table to the driver (again after coreaudiod restarts).
    func sendTable(force: Bool = false) {
        let table = store.library.appRoutes.compactMap { bid, ch -> String? in
            guard let pair = Self.channels.first(where: { $0.0.rawValue == ch })?.1 else { return nil }
            return "\(bid)=\(pair)"
        }.sorted().joined(separator: "\n")
        guard force || table != sentTable else { return }
        let plugIn = Self.plugInObject()
        guard plugIn != 0 else { lastError = "Driver audio NexusDeck non trovato"; return }
        var addr = Self.address(Self.routeSelector)
        var str = table as CFString
        let err = withUnsafeMutablePointer(to: &str) {
            AudioObjectSetPropertyData(plugIn, &addr, 0, nil, UInt32(MemoryLayout<CFString>.size), $0)
        }
        if err == noErr {
            sentTable = table; lastError = nil
        } else {
            lastError = "Aggiorna il driver audio NexusDeck (Impostazioni → Uscita audio) per usare l'instradamento app"
        }
    }

    private static func plugInObject() -> AudioObjectID {
        var addr = address(kAudioHardwarePropertyTranslateBundleIDToPlugIn)
        var bid = driverBundleID as CFString
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<CFString>.size), &bid, &size, &id)
        return id
    }

    // MARK: Process discovery

    private func installListener() {
        guard !listenerInstalled else { return }
        listenerInstalled = true
        for sel in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDevices] {
            var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    // The device list changes when coreaudiod restarts: the driver forgot the table.
                    if sel == kAudioHardwarePropertyDevices { self?.sentTable = nil }
                    self?.scheduleRefresh()
                }
            }
        }
        // "Playing" flags change without a list change: poll lightly.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func scheduleRefresh() {
        refreshWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        refreshWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    private static func address(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids
    }

    private static func pid(_ obj: AudioObjectID) -> pid_t {
        var addr = address(kAudioProcessPropertyPID)
        var v: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v)
        return v
    }

    private static func bundleID(_ obj: AudioObjectID) -> String {
        var addr = address(kAudioProcessPropertyBundleID)
        var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v) == noErr, let s = v else { return "" }
        return s.takeRetainedValue() as String
    }

    private static func isRunningOutput(_ obj: AudioObjectID) -> Bool {
        var addr = address(kAudioProcessPropertyIsRunningOutput)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v)
        return v != 0
    }

    /// The app a process belongs to: helpers ("com.google.Chrome.helper.renderer") map to their main app.
    private static func owningApp(_ bundleID: String, _ pid: pid_t) -> (String, String, NSImage?)? {
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular, let id = app.bundleIdentifier {
            return (id, app.localizedName ?? id, app.icon)
        }
        var parts = bundleID.split(separator: ".").map(String.init)
        while parts.count >= 2 {
            let id = parts.joined(separator: ".")
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.activationPolicy == .regular }) {
                return (id, app.localizedName ?? id, app.icon)
            }
            parts.removeLast()
        }
        return nil
    }

    func refresh() {
        let own = ProcessInfo.processInfo.processIdentifier
        var groups: [String: (name: String, icon: NSImage?, objs: [AudioObjectID], playing: Bool)] = [:]
        for obj in Self.processObjects() {
            let p = Self.pid(obj)
            guard p > 0, p != own else { continue }
            let bid = Self.bundleID(obj)
            guard let (id, name, icon) = Self.owningApp(bid, p), id != Bundle.main.bundleIdentifier else { continue }
            var g = groups[id] ?? (name, icon, [], false)
            g.objs.append(obj)
            g.playing = g.playing || Self.isRunningOutput(obj)
            groups[id] = g
        }
        let list = groups.map { AudioApp(bundleID: $0.key, name: $0.value.name, icon: $0.value.icon, playing: $0.value.playing) }
            .sorted { ($0.playing ? 0 : 1, $0.name.lowercased()) < ($1.playing ? 0 : 1, $1.name.lowercased()) }
        if list != apps { apps = list }

        sendTable()
    }

}
