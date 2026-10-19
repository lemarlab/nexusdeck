import Foundation
import CoreAudio
import AppKit
import Combine

/// Routes audio between the NexusDeck virtual devices and the controller's USB audio interface.
///
/// A private aggregate device (USB interface as clock master + hidden bridge devices with drift
/// compensation) runs one IOProc that copies:
///   USB in 1-2 / 3-4 / 5-6  -> Creator Mix / Audience Mix / Chat Mic bridges
///   System / Game / Chat bridges -> USB out 1-2 / 3-4 / 5-6
///   Line In / Console bridges -> mixed into USB out 1-2 with the gain of their knob
@MainActor
final class AudioBridge: ObservableObject {
    enum Status: Equatable {
        case idle
        case missingPlugIn
        case missingInterface
        case running
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    private static let aggregateUID = "NexusDeck.Aggregate"
    private static let inputBridges = ["NexusDeck.Bridge.System", "NexusDeck.Bridge.Game", "NexusDeck.Bridge.Chat"]
    /// Software channels: no USB channel of their own on the device.
    private static let softBridges = ["NexusDeck.Bridge.LineIn", "NexusDeck.Bridge.Console"]
    private static let outputBridges = ["NexusDeck.Bridge.CreatorMix", "NexusDeck.Bridge.AudienceMix", "NexusDeck.Bridge.ChatMic"]

    private var aggregate: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var listenerInstalled = false
    private var restartWork: DispatchWorkItem?
    /// Real-time copy plan, read by the IO thread.
    private var plan: UnsafeMutablePointer<RoutePlan>?

    struct Route { var srcBuffer: Int32; var srcChannel: Int32; var dstBuffer: Int32; var dstChannel: Int32; var gain: Int32 }
    /// gains: 0 = unity, 1 = Line In, 2 = Console (written by the main thread, read by the IO thread).
    struct RoutePlan {
        var count: Int32
        var gains: (Float, Float, Float)
        var routes: (Route, Route, Route, Route, Route, Route, Route, Route, Route, Route, Route, Route, Route, Route, Route, Route)
    }
    private var softGains: (Float, Float) = (1, 1)

    /// Sets the software gain (0…1) of the Line In and Console virtual outputs.
    func setSoftGains(lineIn: Float, console: Float) {
        softGains = (lineIn, console)
        plan?.pointee.gains.1 = lineIn
        plan?.pointee.gains.2 = console
    }

    static let installedPath = "/Library/Audio/Plug-Ins/HAL/NexusDeckAudio.driver"

    var isPlugInInstalled: Bool { FileManager.default.fileExists(atPath: Self.installedPath) }

    /// Installs (or updates) the bundled audio plug-in. Requires an administrator password.
    func installPlugIn() -> String? {
        guard let src = Bundle.main.url(forResource: "NexusDeckAudio", withExtension: "driver") else { return "Plug-in non incluso nell'app" }
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("NexusDeckAudio.driver")
        try? FileManager.default.removeItem(at: stage)
        do { try FileManager.default.copyItem(at: src, to: stage) } catch { return error.localizedDescription }
        let cmd = "rm -rf '\(Self.installedPath)' && ditto '\(stage.path)' '\(Self.installedPath)' && xattr -cr '\(Self.installedPath)' && chown -R root:wheel '\(Self.installedPath)' && killall coreaudiod"
        return runAdmin(cmd)
    }

    func uninstallPlugIn() -> String? {
        teardown()
        return runAdmin("rm -rf '\(Self.installedPath)' && killall coreaudiod")
    }

    private func runAdmin(_ cmd: String) -> String? {
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(cmd)\" with administrator privileges")?.executeAndReturnError(&err)
        if let err { return err[NSAppleScript.errorMessage] as? String ?? "Errore" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.rebuild() }
        return nil
    }

    /// Requested USB sample rate (48 or 96 kHz). Applied to the controller and to the virtual devices.
    private(set) var sampleRate: Double = 48000

    func start(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        installListener()
        rebuild()
    }

    /// Single Mix routing of the "Creator Mix" device (see makePlan).
    private(set) var singleMix = false

    func setSingleMix(_ on: Bool) {
        guard on != singleMix else { return }
        singleMix = on
        if status == .running { rebuild() }
    }

    func setSampleRate(_ rate: Double) {
        guard rate == 48000 || rate == 96000 else { return }
        sampleRate = rate
        rebuild()
    }

    private func setNominalRate(_ id: AudioObjectID, _ rate: Double) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var current = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &current)
        guard current != rate else { return }
        var r = Float64(rate)
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &r)
        // Wait for the device to switch.
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.05)
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &current)
            if current == rate { break }
        }
    }

    func stop() {
        teardown()
        status = .idle
    }

    // MARK: Device discovery

    private func installListener() {
        guard !listenerInstalled else { return }
        listenerInstalled = true
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
    }

    private func scheduleRebuild() {
        restartWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Ignore changes caused by our own aggregate.
                if self.status == .running, self.interfaceUID() != nil, self.aggregate != 0, self.deviceExists(self.aggregate) { return }
                self.rebuild()
            }
        }
        restartWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: w)
    }

    private func deviceExists(_ id: AudioObjectID) -> Bool { allDevices().contains(id) }

    private func allDevices() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids
    }

    private func stringProperty(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr, let s = v else { return "" }
        return s.takeRetainedValue() as String
    }

    private func device(forUID uid: String) -> AudioObjectID {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cf = uid as CFString
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<CFString>.size), &cf, &size, &id)
        return id
    }

    /// UID of the controller's USB audio interface (class-compliant, handled by macOS).
    private func interfaceUID() -> String? {
        for id in allDevices() {
            let name = stringProperty(id, kAudioObjectPropertyName)
            let maker = stringProperty(id, kAudioObjectPropertyManufacturer)
            if name.contains("AX310") && maker.contains("AVerMedia") { return stringProperty(id, kAudioDevicePropertyDeviceUID) }
        }
        return nil
    }

    private func channelCount(_ id: AudioObjectID, input: Bool) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Per-buffer channel counts of a device, used to address aggregate channels.
    private func bufferLayout(_ id: AudioObjectID, input: Bool) -> [Int] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return [] }
        return UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self)).map { Int($0.mNumberChannels) }
    }

    // MARK: Build

    private func rebuild() {
        teardown()
        guard device(forUID: Self.inputBridges[0]) != 0 else { status = .missingPlugIn; return }
        guard let usb = interfaceUID() else { status = .missingInterface; return }
        // Same rate on the controller and on our devices (the plug-in switches all of them together).
        setNominalRate(device(forUID: usb), sampleRate)
        setNominalRate(device(forUID: Self.inputBridges[0]), sampleRate)

        let subs: [[String: Any]] = [[kAudioSubDeviceUIDKey: usb]]
            + (Self.inputBridges + Self.softBridges.filter { device(forUID: $0) != 0 } + Self.outputBridges).map { [kAudioSubDeviceUIDKey: $0, kAudioSubDeviceDriftCompensationKey: 1] }
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NexusDeck Bridge",
            kAudioAggregateDeviceUIDKey: Self.aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: usb,
            kAudioAggregateDeviceClockDeviceKey: usb,
            kAudioAggregateDeviceSubDeviceListKey: subs,
        ]
        var agg = AudioObjectID(0)
        let err = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &agg)
        guard err == noErr, agg != 0 else { status = .failed("Aggregato non creato (\(err))"); return }
        aggregate = agg

        // Wait until the aggregate has published its streams.
        var tries = 0
        while channelCount(agg, input: true) == 0 && tries < 20 { Thread.sleep(forTimeInterval: 0.05); tries += 1 }

        guard let newPlan = makePlan(usbUID: usb) else { teardown(); status = .failed("Canali non trovati"); return }
        plan = newPlan

        let planPtr = newPlan
        var procID: AudioDeviceIOProcID?
        let r = AudioDeviceCreateIOProcIDWithBlock(&procID, agg, nil) { _, inInput, _, outOutput, _ in
            Self.render(planPtr, inInput, outOutput)
        }
        guard r == noErr, let procID else { teardown(); status = .failed("IOProc non creato (\(r))"); return }
        ioProc = procID
        let s = AudioDeviceStart(agg, procID)
        status = s == noErr ? .running : .failed("Avvio fallito (\(s))")
    }

    /// Maps logical channels to (buffer, channel) pairs in the aggregate's buffer lists.
    private func makePlan(usbUID: String) -> UnsafeMutablePointer<RoutePlan>? {
        let inLayout = bufferLayout(aggregate, input: true)
        let outLayout = bufferLayout(aggregate, input: false)
        func locate(_ layout: [Int], _ flat: Int) -> (Int32, Int32)? {
            var f = flat
            for (b, n) in layout.enumerated() {
                if f < n { return (Int32(b), Int32(f)) }
                f -= n
            }
            return nil
        }
        let usb = device(forUID: usbUID)
        let usbIn = channelCount(usb, input: true)
        let usbOut = channelCount(usb, input: false)
        guard usbIn >= 6, usbOut >= 6 else { return nil }

        var routes: [Route] = []
        // USB inputs 0..5 -> output bridges (after the USB outputs in the aggregate output list).
        for pair in 0..<3 {
            // Single Mix: "Creator Mix" carries the Audience mix (identical to the Master mix, but it keeps
            // the mic when the monitor removes it from the mix the headphones listen to).
            let source = singleMix && pair == 0 ? 1 : pair
            for c in 0..<2 {
                guard let src = locate(inLayout, source * 2 + c), let dst = locate(outLayout, usbOut + pair * 2 + c) else { return nil }
                routes.append(Route(srcBuffer: src.0, srcChannel: src.1, dstBuffer: dst.0, dstChannel: dst.1, gain: 0))
            }
        }
        // Input bridges (after the USB inputs) -> USB outputs 0..5.
        for pair in 0..<3 {
            for c in 0..<2 {
                guard let src = locate(inLayout, usbIn + pair * 2 + c), let dst = locate(outLayout, pair * 2 + c) else { return nil }
                routes.append(Route(srcBuffer: src.0, srcChannel: src.1, dstBuffer: dst.0, dstChannel: dst.1, gain: 0))
            }
        }
        // Line In / Console bridges -> added to USB outputs 0-1 (System channel).
        let softCount = Self.softBridges.filter { device(forUID: $0) != 0 }.count
        for pair in 0..<softCount {
            for c in 0..<2 {
                guard let src = locate(inLayout, usbIn + 6 + pair * 2 + c), let dst = locate(outLayout, c) else { continue }
                routes.append(Route(srcBuffer: src.0, srcChannel: src.1, dstBuffer: dst.0, dstChannel: dst.1, gain: Int32(pair + 1)))
            }
        }
        let p = UnsafeMutablePointer<RoutePlan>.allocate(capacity: 1)
        var r = routes
        let count = r.count
        while r.count < 16 { r.append(Route(srcBuffer: 0, srcChannel: 0, dstBuffer: 0, dstChannel: 0, gain: 0)) }
        p.initialize(to: RoutePlan(count: Int32(count), gains: (1, softGains.0, softGains.1),
                                   routes: (r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13], r[14], r[15])))
        return p
    }

    /// Real-time copy. No allocation or locking.
    nonisolated private static func render(_ plan: UnsafeMutablePointer<RoutePlan>, _ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outs = UnsafeMutableAudioBufferListPointer(output)
        for b in outs { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
        let g = plan.pointee.gains
        withUnsafeBytes(of: plan.pointee.routes) { raw in
            let routes = raw.bindMemory(to: Route.self)
            for i in 0..<Int(plan.pointee.count) {
                let r = routes[i]
                guard Int(r.srcBuffer) < ins.count, Int(r.dstBuffer) < outs.count else { continue }
                let sb = ins[Int(r.srcBuffer)], db = outs[Int(r.dstBuffer)]
                guard let sp = sb.mData?.assumingMemoryBound(to: Float.self), let dp = db.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let sStride = Int(sb.mNumberChannels), dStride = Int(db.mNumberChannels)
                let frames = min(Int(sb.mDataByteSize) / 4 / max(sStride, 1), Int(db.mDataByteSize) / 4 / max(dStride, 1))
                let sc = Int(r.srcChannel), dc = Int(r.dstChannel)
                let k: Float = r.gain == 0 ? g.0 : (r.gain == 1 ? g.1 : g.2)
                if k == 0 { continue }
                for f in 0..<frames { dp[f * dStride + dc] += sp[f * sStride + sc] * k }
            }
        }
    }

    private func teardown() {
        if aggregate != 0 {
            if let ioProc {
                AudioDeviceStop(aggregate, ioProc)
                AudioDeviceDestroyIOProcID(aggregate, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        ioProc = nil
        aggregate = 0
        if let plan { plan.deallocate() }
        plan = nil
    }
}
