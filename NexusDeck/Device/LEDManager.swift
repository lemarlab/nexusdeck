import Foundation
import os

/// Current audio state the LEDs depend on (function-key colours, strip override).
struct LEDAudioState: Equatable {
    /// Colours of the four function keys for the "follow the widget" mode (nil = empty key).
    var functionKeyColors: [String?] = [nil, nil, nil, nil]
    /// Live / recording strip override.
    var auraOverride: LEDSetting?
}

/// Desired LED state of the controller, per target (see LED_PROTOCOL.md).
/// Pure data: built by `compute` and diffed by `LEDManager`.
struct LEDScene: Equatable {
    struct Color: Equatable {
        var r: UInt8
        var g: UInt8
        var b: UInt8

        static let black = Color(r: 0, g: 0, b: 0)
        static let white = Color(r: 255, g: 255, b: 255)
    }

    /// One function key (LED ids 0x3C…0x3F).
    struct Key: Equatable {
        var on: Bool
        var color: Color
    }

    /// One knob ring, or the all-rings group.
    struct Ring: Equatable {
        var sdkMode: Int
        var color: Color
        var speed: UInt8 = 0
        /// LEDs lit, 0…10 (10 = the whole ring).
        var length: UInt8 = 0x0A
    }

    /// Ambient strip (target 12).
    struct Strip: Equatable {
        var sdkMode: Int
        var color: Color
        var speed: UInt8
    }

    /// config1 + the C0 write: all rings with one colour, or one colour per ring.
    enum RingGroup: Equatable {
        case all(Ring)
        case perRing([Ring])

        var sdkMode: Int {
            switch self {
            case .all(let ring): return ring.sdkMode
            case .perRing(let rings): return rings.first?.sdkMode ?? 0
            }
        }
    }

    var functionKeys = Array(repeating: Key(on: false, color: .black), count: 4)
    var ringGroup: RingGroup?
    var aura: Strip?

    // MARK: Desired state

    /// Rebuilds the wanted state from the settings and the current audio state. The firmware draws the knob
    /// volumes by itself (config1), including the Mic ring: the app never takes a ring over.
    static func compute(settings s: DeviceSettings, audio: LEDAudioState) -> LEDScene {
        var scene = LEDScene()

        // Function keys: off, the key's own colour, or one custom colour.
        for i in 0..<4 {
            let source = s.ledButton.colorSource
            let widget = i < audio.functionKeyColors.count ? audio.functionKeyColors[i] : nil
            let on = s.ledButton.mode != .off && (source != .widget || widget != nil)
            let hex: String
            switch source {
            case .widget: hex = widget ?? "#000000"
            case .perItem: hex = i < s.ledButton.itemColors.count ? s.ledButton.itemColors[i] : s.ledButton.colorHex
            case .single: hex = s.ledButton.colorHex
            }
            scene.functionKeys[i] = Key(on: on, color: rgb(hex, brightness: s.ledButton.brightness))
        }

        // Knob rings: config1 + group C0, or one colour per ring.
        let effect = AXProtocol.ledEffect(mode: s.ledKnob.mode.rawValue, peak: s.ledKnob.peak)
        let speed: UInt8 = effect.speed ? UInt8(clamping: s.ledKnob.speed) : 0
        if s.ledKnob.colorSource == .perItem && s.ledKnob.mode.usesColor {
            let rings = (0..<6).map { i -> Ring in
                let hex = i < s.ledKnob.itemColors.count ? s.ledKnob.itemColors[i] : s.ledKnob.colorHex
                return Ring(sdkMode: effect.sdk, color: rgb(hex, brightness: s.ledKnob.brightness), speed: speed)
            }
            scene.ringGroup = .perRing(rings)
        } else {
            let color = effect.white ? Color.white : rgb(s.ledKnob.colorHex, brightness: s.ledKnob.brightness)
            scene.ringGroup = .all(Ring(sdkMode: effect.sdk, color: color, speed: speed))
        }

        // Ambient strip.
        let led = audio.auraOverride ?? s.ledAura
        let aura = AXProtocol.ledEffect(mode: led.mode.rawValue, peak: led.peak)
        let color: Color = led.mode == .off ? .black
            : (aura.white ? .white : rgb(led.colorHex, brightness: led.brightness))
        scene.aura = Strip(sdkMode: aura.sdk, color: color, speed: aura.speed ? UInt8(clamping: led.speed) : 0)
        return scene
    }

    private static func rgb(_ hex: String, brightness: Int) -> Color {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        let k = Double(max(0, min(100, brightness))) / 100
        return Color(r: UInt8(Double((v >> 16) & 0xFF) * k),
                     g: UInt8(Double((v >> 8) & 0xFF) * k),
                     b: UInt8(Double(v & 0xFF) * k))
    }
}

/// Single writer for the controller LEDs: diffs the desired scene against what was sent and writes only the
/// changed targets. The firmware owns the knob rings (Mic ring included).
@MainActor
final class LEDManager {
    enum Reason: String {
        case attach, diff
    }

    /// Every LED write is logged to the unified log when this flag is on.
    static var debugLogging: Bool { UserDefaults.standard.bool(forKey: "LEDDebugLog") }

    private(set) var desired = LEDScene()
    private(set) var sent = LEDScene()
    private(set) var isAttached = false
    weak var service: AudioService?

    private var controller: AXController?
    private var flushTask: Task<Void, Never>?
    private var flushToken = 0
    /// Last config1 value read from (or written to) the device: the closing write keeps its unknown bits.
    private var lastConfig1: UInt8?
    /// A flush is due: the scene changed (last write wins, the latest `desired` is read at flush time).
    private var dirty = false
    private var pendingForce = false

    private static let logHandle = OSLog(subsystem: "NexusDeck", category: "LED")

    // MARK: Lifecycle

    /// Full send of the wanted state, then live updates.
    func attach(_ controller: AXController) {
        flushTask?.cancel(); flushTask = nil
        self.controller = controller
        isAttached = true
        sent = LEDScene()
        refreshDesired()
        scheduleFlush(force: true, delay: .zero)
    }

    /// Stops the timers and clears the state (the controller is gone).
    func detach() {
        isAttached = false
        controller = nil
        stopTimers()
        desired = LEDScene()
        sent = LEDScene()
        lastConfig1 = nil
        dirty = false
        pendingForce = false
    }

    /// The mixer was found out of sync at start-up: forget what was sent and write the whole scene again.
    func reassert() {
        guard isAttached else { return }
        sent = LEDScene()
        controller?.invalidateWriteCache()
        scheduleFlush(force: true)
    }

    /// Recomputes the scene from the settings and the current audio state.
    func update() {
        refreshDesired()
        scheduleFlush()
    }

    /// Only updates the desired state and schedules a flush.
    func setScene(_ scene: LEDScene) {
        desired = scene
        scheduleFlush()
    }

    /// Quit: every LED off (strip, function keys, rings), as the reference app does.
    func allOff() {
        // Before attach the manager has no controller yet: the service still has the device.
        guard let c = controller ?? service?.controller else { return }
        isAttached = false
        stopTimers()
        var cmds: [AXProtocol.Command] = []
        for i in 0..<4 { cmds.append(AXProtocol.functionKeyLED(index: i, on: false, r: 0, g: 0, b: 0)) }
        // Ring mode 0 first (bits 1–2 cleared, as setClosingLeds): the group write alone leaves the level display on.
        var closing = AXProtocol.config1((lastConfig1 ?? 0) & ~0x06)
        closing.preDelayMs = 120
        cmds.append(closing)
        cmds.append(AXProtocol.knobRings(sdkMode: 0, r: 0, g: 0, b: 0, speed: 0))
        // The strip goes last and twice: right after the panel images its first write can be dropped.
        let stripOff = AXProtocol.auraStrip(sdkMode: 0, r: 0, g: 0, b: 0, speed: 0)
        cmds += [stripOff, stripOff]
        for var cmd in cmds { cmd.preDelayMs = 120; c.sendAndWait(cmd, timeout: 0.6) }
        sent = LEDScene()
    }

    // MARK: Queries used by AudioService

    /// First strip write, sent seconds before the LEDs come on so the strip lights straight in its colour.
    func auraPrimer() -> AXProtocol.Command? {
        guard let service else { return nil }
        let scene = LEDScene.compute(settings: service.store.library.device, audio: service.ledAudioState())
        guard let aura = scene.aura else { return nil }
        return AXProtocol.auraStrip(sdkMode: aura.sdkMode, r: aura.color.r, g: aura.color.g,
                                    b: aura.color.b, speed: aura.speed)
    }

    // MARK: Timers

    private func stopTimers() {
        flushTask?.cancel()
        flushTask = nil
    }

    // MARK: Flush

    private func refreshDesired() {
        guard let service else { return }
        desired = LEDScene.compute(settings: service.store.library.device, audio: service.ledAudioState())
    }

    /// Coalesces a burst of updates: the latest change is always sent (never dropped).
    private func scheduleFlush(force: Bool = false, delay: Duration = .milliseconds(300)) {
        guard isAttached else { return }
        dirty = true
        if force { pendingForce = true }
        guard flushTask == nil else { return }
        flushToken += 1
        let token = flushToken
        flushTask = Task { [weak self] in
            guard let self else { return }
            var wait = delay
            while self.dirty, self.isAttached, !Task.isCancelled {
                if wait > .zero { try? await Task.sleep(for: wait) }
                guard !Task.isCancelled else { break }
                self.dirty = false
                let force = self.pendingForce
                self.pendingForce = false
                await self.flush(reason: force ? .attach : .diff, force: force)
                // A change arrived while flushing: send it after a short pause too.
                wait = .milliseconds(300)
            }
            // Only the task that owns the slot clears it (a newer flush may have replaced it).
            if self.flushToken == token { self.flushTask = nil }
        }
    }

    private func flush(reason: Reason, force: Bool = false) async {
        guard isAttached, let c = controller else { return }
        let scene = desired
        let previous = sent
        var cmds: [(target: String, command: AXProtocol.Command)] = []

        for (i, key) in scene.functionKeys.enumerated() {
            let old = i < previous.functionKeys.count ? previous.functionKeys[i] : nil
            if force || old != key {
                cmds.append(("fnkey \(i)", AXProtocol.functionKeyLED(index: i, on: key.on,
                                                                    r: key.color.r, g: key.color.g, b: key.color.b)))
            }
        }

        if let group = scene.ringGroup, force || previous.ringGroup != group {
            // config1 first, then the group write: it must never follow its C0 write.
            if let reply = await c.transact(AXProtocol.readConfig1()), reply.count > 4 {
                // The flush may have been cancelled (detach / attach) while waiting for the reply.
                guard !Task.isCancelled, controller === c else { return }
                let cfg = Self.config1(current: reply[4], sdkMode: group.sdkMode)
                lastConfig1 = cfg
                if cfg != reply[4] {
                    var cmd = AXProtocol.config1(cfg)
                    cmd.preDelayMs = 0
                    cmds.append(("config1", cmd))
                }
            }
            guard !Task.isCancelled, controller === c else { return }
            switch group {
            case .all(let ring):
                cmds.append(("rings", AXProtocol.knobRings(sdkMode: ring.sdkMode, r: ring.color.r,
                                                           g: ring.color.g, b: ring.color.b, speed: ring.speed)))
            case .perRing(let rings):
                let old: [LEDScene.Ring]? = {
                    switch previous.ringGroup {
                    case .perRing(let rings): return rings
                    default: return nil
                    }
                }()
                for (i, ring) in rings.enumerated() {
                    let unchanged = old.map { i < $0.count && $0[i] == ring } ?? false
                    guard force || !unchanged else { continue }
                    cmds.append(("ring \(i)", AXProtocol.knobRing(i, sdkMode: ring.sdkMode, r: ring.color.r,
                                                                 g: ring.color.g, b: ring.color.b,
                                                                 speed: ring.speed, length: ring.length)))
                }
            }
        }

        if let aura = scene.aura, force || previous.aura != aura {
            let cmd = AXProtocol.auraStrip(sdkMode: aura.sdkMode, r: aura.color.r, g: aura.color.g,
                                           b: aura.color.b, speed: aura.speed)
            // Written twice: the mixer often drops a single strip write.
            cmds.append(("aura", cmd))
            cmds.append(("aura", cmd))
        }

        if !cmds.isEmpty {
            if Self.debugLogging {
                for (target, command) in cmds {
                    Self.log("\(reason.rawValue) \(target) [\(Self.hex(command.bytes))] → queued")
                }
            }
            c.sendInOrder(cmds.map(\.command))
        } else if Self.debugLogging {
            Self.log("\(reason.rawValue) no change")
        }

        sent = scene
    }

    /// config1 value for an SDK mode: keeps the unknown bits of the current one.
    private static func config1(current: UInt8, sdkMode: Int) -> UInt8 {
        if sdkMode == 0 { return current & ~0x06 }
        if sdkMode == 7 { return (current & ~0x0E) | 0x0A }
        return (current & ~0x0E) | 0x0C
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func log(_ message: String) {
        os_log("%{public}@", log: logHandle, type: .debug, message)
    }
}
