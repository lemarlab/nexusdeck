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
    private static let visibleSelector: AudioObjectPropertySelector = 0x6E64_766D // 'ndvm'
    private static let namesSelector: AudioObjectPropertySelector = 0x6E64_6E6D // 'ndnm'
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

    // MARK: Visible devices

    private var sentMask: UInt32?
    private var wantedMask: UInt32 = 0xFFFF_FFFF

    /// Publishes only the devices that are in use: Creator/Audience Mix with Dual Mix, the "(OBS)" inputs with
    /// the OBS tracks mode. Device indices as in the driver's table.
    func setVisibility(dualMix: Bool, obsTracks: Bool) {
        var m: UInt32 = 0
        for i in 2...7 { m |= 1 << i }                       // Chat Mic, System, Game, Chat, Line In, Console
        if dualMix { m |= 1 << 0 }                            // Creator Mix
        if dualMix && !obsTracks { m |= 1 << 1 }              // Audience Mix (Line In only in OBS tracks mode)
        if obsTracks { for i in 16...20 { m |= 1 << i } }     // System/Game/Chat/Line In/Console (OBS)
        wantedMask = m
        sendVisibility()
    }

    /// Quit: the NexusDeck devices disappear from the Mac (they do not work without the app), so apps fall back
    /// to another output. The output in use is remembered and selected again at the next start.
    func hideAllDevices() {
        let def = Self.defaultOutputUID()
        if def.hasPrefix("NexusDeck.") { UserDefaults.standard.set(def, forKey: "audio.lastDefaultOutput") }
        wantedMask = 0
        sentMask = nil
        sendVisibility()
    }

    /// Start: once the devices are back, the output that was in use when NexusDeck quit is selected again.
    func restoreDefaultOutput() {
        guard let uid = UserDefaults.standard.string(forKey: "audio.lastDefaultOutput") else { return }
        UserDefaults.standard.removeObject(forKey: "audio.lastDefaultOutput")
        for delay in [0.5, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard Self.defaultOutputUID() != uid else { return }
                var addr = Self.address(kAudioHardwarePropertyTranslateUIDToDevice)
                var cf = uid as CFString
                var id = AudioObjectID(0)
                var size = UInt32(MemoryLayout<AudioObjectID>.size)
                AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<CFString>.size), &cf, &size, &id)
                guard id != 0 else { return }
                for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
                    var a = Self.address(sel)
                    AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)
                }
            }
        }
    }

    private static func defaultOutputUID() -> String {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        var uaddr = address(kAudioDevicePropertyDeviceUID)
        var s: Unmanaged<CFString>?
        var ssize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &uaddr, 0, nil, &ssize, &s) == noErr, let str = s else { return "" }
        return str.takeRetainedValue() as String
    }

    private func sendVisibility() {
        guard sentMask != wantedMask else { return }
        let plugIn = Self.plugInObject()
        guard plugIn != 0 else { return }
        var addr = Self.address(Self.visibleSelector)
        var num = NSNumber(value: Int64(wantedMask)) as CFNumber
        let err = withUnsafeMutablePointer(to: &num) {
            AudioObjectSetPropertyData(plugIn, &addr, 0, nil, UInt32(MemoryLayout<CFNumber>.size), $0)
        }
        if err == noErr { sentMask = wantedMask }
    }

    // MARK: Device names

    private var sentNames: String?
    private var wantedNames = ""

    /// Renames the Mac devices after the custom channel names (also their "(OBS)" inputs).
    func setNames(_ mixer: MixerProfile) {
        let devices: [(MixerChannel, Int, Int)] = [(.system, 3, 16), (.game, 4, 17), (.chat, 5, 18), (.lineIn, 6, 19), (.console, 7, 20)]
        var lines: [String] = []
        for (ch, out, cap) in devices {
            let n = (mixer.channelNames[ch.rawValue] ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\n", with: " ")
            guard !n.isEmpty else { continue }
            lines.append("\(out)=\(n)")
            lines.append("\(cap)=\(n)")
        }
        wantedNames = lines.joined(separator: "\n")
        sendNames()
    }

    private func sendNames() {
        guard sentNames != wantedNames else { return }
        let plugIn = Self.plugInObject()
        guard plugIn != 0 else { return }
        var addr = Self.address(Self.namesSelector)
        var str = wantedNames as CFString
        let err = withUnsafeMutablePointer(to: &str) {
            AudioObjectSetPropertyData(plugIn, &addr, 0, nil, UInt32(MemoryLayout<CFString>.size), $0)
        }
        if err == noErr { sentNames = wantedNames }
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
                    if sel == kAudioHardwarePropertyDevices { self?.sentTable = nil; self?.sentMask = nil; self?.sendVisibility(); self?.sentNames = nil; self?.sendNames() }
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
