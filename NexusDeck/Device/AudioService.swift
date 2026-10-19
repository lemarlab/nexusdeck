import Foundation
import Combine

/// Keeps the hardware mixer, mic DSP and device settings in sync with the active profiles.
@MainActor
final class AudioService: ObservableObject {
    @Published var meters: [MixBus: [MixerChannel: Int]] = [:] { didSet { LevelMeters.shared.values = meters } }
    @Published var outputMeters: [MixBus: Int] = [:]

    let store: ProfileStore
    var controller: AXController?

    init(store: ProfileStore) {
        self.store = store
    }

    static func hw(_ level: Int) -> Int { Int((Double(level) / 100 * Double(AXProtocol.mixerVolumeMax)).rounded()) }
    static func ui(_ hw: Int) -> Int { min(100, hw * 100 / AXProtocol.mixerVolumeMax) }

    // MARK: Full sync

    func applyAll() {
        applyMixer()
        applyMic()
        applyDSP()
        applyDevice()
        applyLEDs(force: true)
    }

    func applyMixer() {
        guard let c = controller else { return }
        let p = store.mixer
        for bus in MixBus.allCases {
            let mix = p.mixes[p.dualMix ? bus : .creator] ?? MixState()
            let values = MixerChannel.allCases.map { ch -> Int in
                let s = mix.channels[ch] ?? ChannelState()
                return Self.hw(s.level * mix.level / 100)
            }
            c.send(AXProtocol.mixerVolumes(mixer: bus.rawValue, values: values))
        }
        c.send(AXProtocol.mixerMutes(muteMasks()))
        c.send(AXProtocol.knobControl(mixer: p.dualMix ? p.activeMix.rawValue : 0, linked: !p.dualMix))
        // The monitor overrides the mic volume in some mixes: re-apply it after the volumes.
        applyMic()
        if ducked { applyDucking() }
    }

    // MARK: Mic state per output
    //
    // Outputs: headphones = Creator mix, stream = Audience mix, chat = Chat Mic mix (verified on the device:
    // it carries the mic only; bit0 of the third mute byte mutes it).

    /// Temporary mute while the cough / bleep key is held (nil = not held).
    @Published private(set) var coughMode: MicMuteMode?

    private func micMuted(_ bus: MixBus) -> Bool {
        let mix = store.mixer.mixes[bus] ?? MixState()
        return (mix.channels[.mic]?.muted ?? false) || mix.muted
    }

    private func coughs(_ out: RouteOutput) -> Bool {
        guard let m = coughMode else { return false }
        switch m {
        case .all: return true
        case .stream: return out == .stream
        case .chat: return out == .chat
        }
    }

    /// The mic is heard in the headphones only with the monitor on and the mic not muted.
    private var hearsMic: Bool {
        store.mixer.micMonitor && !micMuted(.creator) && store.mixer.isRouted(.mic, to: .headphones) && !coughs(.headphones)
    }

    var micInStream: Bool { !micMuted(.audience) && store.mixer.isRouted(.mic, to: .stream) && !coughs(.stream) }

    private func muteMasks() -> [UInt8] {
        let p = store.mixer
        var masks: [UInt8] = []
        for bus in MixBus.allCases {
            let mix = p.mixes[p.dualMix ? bus : .creator] ?? MixState()
            let out: RouteOutput = bus == .creator ? .headphones : .stream
            var m: UInt8 = 0
            for (i, ch) in MixerChannel.allCases.enumerated() where ch != .mic {
                if mix.muted || (mix.channels[ch]?.muted ?? false) || !p.isRouted(ch, to: out) { m |= 1 << i }
            }
            if bus == .creator ? !hearsMic : !micInStream { m |= 1 }
            masks.append(m)
        }
        masks.append(micInChatMix ? 0 : 1)
        return masks
    }

    /// Chat Mic output: muted on its own, by the "all" mute, by routing or by the cough key.
    private var micInChatMix: Bool {
        let p = store.mixer
        let allMuted = micMuted(.creator) && micMuted(.audience)
        return !p.chatMicMuted && !allMuted && p.isRouted(.mic, to: .chat) && !coughs(.chat)
    }

    /// The channel is muted (by the user or the routing matrix) in some mix on the device.
    func hasMuteBit(channel i: Int) -> Bool {
        muteMasks().prefix(2).contains { $0 & (1 << i) != 0 }
    }

    func sendMutes() {
        controller?.sendInOrder([AXProtocol.mixerMutes(muteMasks())])
    }

    // MARK: Mic mute modes, cough and bleep

    /// Mic knob press / mute action, according to the chosen mode.
    func toggleMicMute(_ mode: MicMuteMode? = nil) {
        let mode = mode ?? store.mixer.micMuteMode
        switch mode {
        case .all:
            let muted = !(micMuted(.audience) && micMuted(.creator) && store.mixer.chatMicMuted)
            for b in MixBus.allCases { store.mixer.mixes[b, default: MixState()].channels[.mic, default: ChannelState()].muted = muted }
            store.mixer.chatMicMuted = muted
        case .stream:
            store.mixer.mixes[.audience, default: MixState()].channels[.mic, default: ChannelState()].muted.toggle()
        case .chat:
            store.mixer.chatMicMuted.toggle()
        }
        applyMic()
    }

    func setCough(_ mode: MicMuteMode?) {
        coughMode = mode
        applyMic()
    }

    func setRoute(_ ch: MixerChannel, _ out: RouteOutput, _ on: Bool) {
        store.mixer.routes["\(out.rawValue).\(ch.rawValue)"] = on ? nil : false
        if ch == .mic { applyMic() } else { sendMutes() }
    }

    // MARK: Ducking

    @Published private(set) var ducked = false
    private var lastSpeech = Date.distantPast

    private func duckingTick() {
        let d = store.mixer.ducking
        guard d.enabled else { if ducked { setDucked(false) }; return }
        if micInputDB > d.thresholdDB && micInStream { lastSpeech = Date() }
        let should = Date().timeIntervalSince(lastSpeech) * 1000 < d.releaseMs
        if should != ducked { setDucked(should) }
    }

    /// Lowered volume step whose gain is `reduction` dB below the one of `base` (gain table of the device).
    private static func duckedStep(_ base: Int, _ reductionDB: Double) -> Int {
        guard base > 0 else { return 0 }
        let target = Double(meterGain[min(20, base)]) * pow(10, -reductionDB / 20)
        return (0...base).last { Double(meterGain[$0]) <= target } ?? 0
    }

    private func setDucked(_ on: Bool) {
        ducked = on
        applyDucking()
    }

    /// Writes the (possibly lowered) volumes of the ducked channels.
    func applyDucking() {
        guard let c = controller else { return }
        let p = store.mixer
        let d = p.ducking
        let buses: [MixBus] = d.streamOnly ? [.audience] : (p.dualMix ? MixBus.allCases : [.creator, .audience])
        var cmds: [AXProtocol.Command] = []
        for name in d.channels {
            guard let ch = MixerChannel(rawValue: name), ch != .mic, let index = MixerChannel.allCases.firstIndex(of: ch) else { continue }
            for b in buses {
                let mix = p.mixes[p.dualMix ? b : .creator] ?? MixState()
                let base = Self.hw((mix.channels[ch]?.level ?? 50) * mix.level / 100)
                let value = ducked && d.enabled ? Self.duckedStep(base, d.reductionDB) : base
                var cmd = AXProtocol.mixerVolume(mixer: b.rawValue, channel: index, value: value)
                cmd.preDelayMs = 0
                cmds.append(cmd)
            }
        }
        if !cmds.isEmpty { c.sendInOrder(cmds) }
    }

    func applyMic() {
        guard let c = controller else { return }
        let p = store.mixer
        // Register 0x20, as the reference app (Ax310Dealer::initKnob → setMicMode):
        // bit0 phantom power, bits 1/2 = Creator/Audience mix get the mic WITH effects (always on),
        // bit3 = Chat Mic with effects (setting), bit4 = 6.3 mm jack input.
        var cfg: UInt8 = (p.phantom48V ? 0x01 : 0) | 0x02 | 0x04
        if store.library.device.chatMicWithEffects { cfg |= 0x08 }
        if p.micInput == .jack63 { cfg |= 0x10 }
        c.send(AXProtocol.micConfig(cfg))
        // Monitor (hearing your own mic in the headphones), verified on the device:
        // - the headphones listen to the Creator mix (register 0x15 = 0);
        // - the firmware ties the Mic knob, its ring and its mute to the Audience mix (the stream);
        // - monitor off = mic muted in the Creator mix + register 0x22 = 0x01, which closes the Chat Mic path
        //   to the headphones without the firmware re-syncing the mic (0x12 = monitor on).
        // In Single Mix the Mac's "Creator Mix" device is then fed from the Audience mix (see AudioBridge),
        // so apps always receive the voice.
        // As enableMonitor in the reference app: a muted mic is treated like monitor off (nothing in the headphones).
        // 0x22 = 0x01 permanently (verified): the Chat Mic mix is not heard in the headphones and the firmware
        // does not re-sync the mic, so each output's mic mute can be set freely.
        c.sendInOrder([AXProtocol.micMonitor(mixer: 1, sync: 0),
                       AXProtocol.headphoneSource(0),
                       AXProtocol.mixerMutes(muteMasks())].map { var x = $0; x.preDelayMs = 0; return x })
        c.send(AXProtocol.preampGain(MicGain.register(p.currentGainDB)))
    }

    func applyDSP() {
        guard let c = controller else { return }
        let d = store.dsp
        c.send(AXProtocol.eqEnable(d.eqEnabled))
        if d.eqEnabled { for (i, b) in d.currentEQ.enumerated() { c.send(AXProtocol.eqBand(index: i, b)) } }
        c.send(AXProtocol.noiseGateEnable(d.noiseGateEnabled))
        if d.noiseGateEnabled { c.send(AXProtocol.noiseGate(d.noiseGate)) }
        c.send(AXProtocol.compressorEnable(d.compressorEnabled))
        if d.compressorEnabled {
            let comp = d.compressorPresets[min(d.compressorPresetIndex, d.compressorPresets.count - 1)]
            c.send(AXProtocol.compressor(d.compressorPresets[0], comp, makeup: d.makeupGain))
        }
        let anyReverb = d.reverbEnabled || d.echoEnabled
        c.send(AXProtocol.reverbMaster(anyReverb))
        if anyReverb {
            var r = d.reverbPresets[min(d.reverbPresetIndex, d.reverbPresets.count - 1)]
            if !d.reverbEnabled { r.gain = -96; r.wetGain = -96 }
            var e = d.echo
            if !d.echoEnabled { e.gain = -96 }
            c.send(AXProtocol.reverb(r, echo: e))
        }
        c.send(AXProtocol.voiceChanger(d.voiceChanger.rawValue))
    }

    func applyDevice() {
        guard let c = controller else { return }
        let s = store.library.device
        c.send(AXProtocol.backlight(s.brightness))
        c.send(AXProtocol.powerSaving(enabled: s.powerSavingMinutes > 0, minutes: s.powerSavingMinutes))
        c.send(AXProtocol.headphoneVolume(Self.hw(s.headphonesVolume)))
        c.send(AXProtocol.lineOutVolume(Self.hw(s.lineOutVolume)))
        c.send(AXProtocol.lineOutSource(store.mixer.dualMix ? s.lineOutSource : (s.lineOutSource == 2 ? 2 : 0)))
    }

    /// Screen only (brightness / power saving): nothing else is rewritten.
    func applyScreen() {
        guard let c = controller else { return }
        let s = store.library.device
        c.send(AXProtocol.backlight(s.brightness))
        c.send(AXProtocol.powerSaving(enabled: s.powerSavingMinutes > 0, minutes: s.powerSavingMinutes))
    }

    static func rgb(_ hex: String, brightness: Int = 100) -> (UInt8, UInt8, UInt8) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        let k = Double(max(0, min(100, brightness))) / 100
        return (UInt8(Double((v >> 16) & 0xFF) * k), UInt8(Double((v >> 8) & 0xFF) * k), UInt8(Double(v & 0xFF) * k))
    }

    /// Colors of the four function keys for the "follow key icon" mode.
    var functionKeyColors: () -> [String?] = { [nil, nil, nil, nil] }
    /// Overrides the ambient strip (live / recording indicators).
    var auraOverride: LEDSetting?
    private var ledTask: Task<Void, Never>?

    enum LEDGroup: Hashable { case knobs, aura, buttons }
    private var pendingLEDs: Set<LEDGroup> = []
    private var lastSentLEDs: DeviceSettings?
    /// Last state written to each knob ring (per-knob colors), to send only what changed.
    private var lastRings: [String]?

    /// Debounced: only groups whose settings changed are sent, once the user stops dragging.
    func applyLEDs(force: Bool = false) {
        guard controller != nil else { return }
        let s = store.library.device
        let last = force ? nil : lastSentLEDs
        if force { lastRings = nil }
        if last?.ledKnob != s.ledKnob { pendingLEDs.insert(.knobs) }
        if last?.ledAura != s.ledAura || force { pendingLEDs.insert(.aura) }
        if last?.ledButton != s.ledButton || force { pendingLEDs.insert(.buttons) }
        lastSentLEDs = s
        guard !pendingLEDs.isEmpty else { return }
        ledTask?.cancel()
        ledTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, let c = self.controller else { return }
            let groups = self.pendingLEDs
            self.pendingLEDs.removeAll()
            let s = self.store.library.device

            if groups.contains(.knobs) {
                let k = AXProtocol.ledEffect(mode: s.ledKnob.mode.rawValue, peak: s.ledKnob.peak)
                // Rewriting config1 resets the rings for a moment: only when the effect really changes.
                if let reply = await c.transact(AXProtocol.readConfig1()), reply.count > 4 {
                    var cfg = reply[4] & ~0x0E
                    if k.sdk == 0 { cfg = reply[4] & ~0x06 } else if k.sdk == 7 { cfg |= 0x0A } else { cfg |= 0x0C }
                    if cfg != reply[4] { c.send(AXProtocol.config1(cfg)); self.lastRings = nil }
                }
                let speed = k.speed ? UInt8(s.ledKnob.speed) : 0
                if s.ledKnob.colorSource == .perItem && s.ledKnob.mode.usesColor {
                    var sent = self.lastRings ?? [String](repeating: "", count: 6)
                    for i in 0..<6 {
                        let kc = Self.rgb(s.ledKnob.itemColors[i], brightness: s.ledKnob.brightness)
                        let sig = "\(k.sdk)-\(speed)-\(kc.0)-\(kc.1)-\(kc.2)"
                        // Only the rings that changed are rewritten.
                        if sent[i] == sig { continue }
                        c.send(AXProtocol.knobRing(i, sdkMode: k.sdk, r: kc.0, g: kc.1, b: kc.2, speed: speed))
                        sent[i] = sig
                    }
                    self.lastRings = sent
                } else {
                    let kc = k.white ? (UInt8(255), UInt8(255), UInt8(255)) : Self.rgb(s.ledKnob.colorHex, brightness: s.ledKnob.brightness)
                    c.send(AXProtocol.knobRings(sdkMode: k.sdk, r: kc.0, g: kc.1, b: kc.2, speed: speed))
                    self.lastRings = nil
                }
            }
            if groups.contains(.aura) { self.sendAura(self.auraOverride ?? s.ledAura) }
            if groups.contains(.buttons) { await self.sendFunctionKeyLEDs() }
        }
    }

    /// Function key LEDs: off, the key's own background color, or one custom color.
    func sendFunctionKeyLEDs() async {
        guard let c = controller else { return }
        let s = store.library.device
        let colors = functionKeyColors()
        for i in 0..<4 {
            let source = s.ledButton.colorSource
            let on = s.ledButton.mode != .off && (source != .widget || colors[i] != nil)
            let hex: String
            switch source {
            case .widget: hex = colors[i] ?? "#000000"
            case .perItem: hex = s.ledButton.itemColors[i]
            case .single: hex = s.ledButton.colorHex
            }
            let col = Self.rgb(hex, brightness: s.ledButton.brightness)
            c.send(AXProtocol.functionKeyLED(index: i, on: on, r: col.0, g: col.1, b: col.2))
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    func sendAura(_ led: LEDSetting) {
        guard let c = controller else { return }
        let e = AXProtocol.ledEffect(mode: led.mode.rawValue, peak: led.peak)
        let col = led.mode == .off ? (UInt8(0), UInt8(0), UInt8(0)) : (e.white ? (UInt8(255), UInt8(255), UInt8(255)) : Self.rgb(led.colorHex, brightness: led.brightness))
        let cmd = AXProtocol.auraStrip(sdkMode: e.sdk, r: col.0, g: col.1, b: col.2, speed: e.speed ? UInt8(led.speed) : 0)
        c.send(cmd)
        c.send(cmd)
    }

    // MARK: Edits from UI / actions

    /// A volume write unmutes the channel on the device (verified for the mic): re-send the mutes after it.
    func reassertMutes() {
        controller?.send(AXProtocol.mixerMutes(muteMasks()))
    }

    func setLevel(_ ch: MixerChannel, bus: MixBus, _ level: Int) {
        let l = max(0, min(100, level))
        let target: MixBus = store.mixer.dualMix ? bus : .creator
        store.mixer.mixes[target, default: MixState()].channels[ch, default: ChannelState()].level = l
        let mix = store.mixer.mixes[target] ?? MixState()
        let hwBuses: [MixBus] = store.mixer.dualMix ? [bus] : MixBus.allCases
        for b in hwBuses {
            controller?.send(AXProtocol.mixerVolume(mixer: b.rawValue, channel: MixerChannel.allCases.firstIndex(of: ch)!, value: Self.hw(l * mix.level / 100)))
        }
        if ch == .mic { applyMic() } else { reassertMutes() }
    }

    func setBusLevel(_ bus: MixBus, _ level: Int) {
        store.mixer.mixes[bus, default: MixState()].level = max(0, min(100, level))
        applyMixer()
    }

    func toggleMute(_ ch: MixerChannel, bus: MixBus) {
        let cur = store.mixer.mixes[bus]?.channels[ch]?.muted ?? false
        setMute(ch, buses: [bus], !cur)
    }

    func setMute(_ ch: MixerChannel, buses: [MixBus], _ muted: Bool) {
        for b in buses { store.mixer.mixes[b, default: MixState()].channels[ch, default: ChannelState()].muted = muted }
        controller?.send(AXProtocol.mixerMutes(muteMasks()))
        if ch == .mic { applyMic() }
    }

    func toggleBusMute(_ bus: MixBus) {
        store.mixer.mixes[bus, default: MixState()].muted.toggle()
        controller?.send(AXProtocol.mixerMutes(muteMasks()))
        applyMic()
    }

    func setMonitor(_ ch: MixerChannel, bus: MixBus, _ on: Bool) {
        store.mixer.micMonitor = on
        applyMic()
    }

    func setDualMix(_ on: Bool) {
        store.mixer.dualMix = on
        if !on { store.mixer.activeMix = .creator }
        if on, store.mixer.mixes[.audience] == nil { store.mixer.mixes[.audience] = store.mixer.mixes[.creator] }
        applyMixer(); applyMic(); applyDevice()
    }

    func switchActiveMix() {
        guard store.mixer.dualMix else { return }
        store.mixer.activeMix = store.mixer.activeMix == .creator ? .audience : .creator
        controller?.send(AXProtocol.knobControl(mixer: store.mixer.activeMix.rawValue, linked: false))
    }

    /// Absolute knob value 0...20 reported by hardware knob i.
    func knobMoved(_ index: Int, hwValue: Int) {
        guard index < MixerChannel.allCases.count else { return }
        let ch = MixerChannel.allCases[index]
        let level = Self.ui(hwValue)
        let b: MixBus = store.mixer.dualMix ? store.mixer.activeMix : .creator
        store.mixer.mixes[b, default: MixState()].channels[ch, default: ChannelState()].level = level
        if ch == .mic { applyMic() }
    }

    /// A mixer knob was pressed: its channel mute flips in the mix the knobs drive (both mixes in Single Mix).
    func knobToggledMute(_ index: Int) {
        guard index < MixerChannel.allCases.count else { return }
        let ch = MixerChannel.allCases[index]
        if ch == .mic { toggleMicMute(); return }
        let buses: [MixBus] = store.mixer.dualMix ? [store.mixer.activeMix] : MixBus.allCases
        let muted = !(store.mixer.mixes[buses[0]]?.channels[ch]?.muted ?? false)
        for b in buses { store.mixer.mixes[b, default: MixState()].channels[ch, default: ChannelState()].muted = muted }
        controller?.send(AXProtocol.mixerMutes(muteMasks()))
        if ch == .mic { applyMic() }
    }

    /// Mute masks read from the mixer (registers 0x11/0x12, bit = channel Mic…Chat), after a knob press.
    /// The firmware toggles the Mic knob's mute in the Audience mix only: in Single Mix a change in either
    /// mix is applied to both, so the two mixes stay identical.
    func mirrorMutes(_ masks: [UInt8]) {
        guard masks.count >= 2 else { return }
        var changed = false
        var micChanged = false
        if store.mixer.dualMix {
            for b in MixBus.allCases {
                for (i, ch) in MixerChannel.allCases.enumerated() {
                    let muted = masks[b.rawValue] & (1 << i) != 0
                    if store.mixer.mixes[b]?.channels[ch]?.muted != muted {
                        store.mixer.mixes[b, default: MixState()].channels[ch, default: ChannelState()].muted = muted
                        if ch == .mic { micChanged = true }
                    }
                }
            }
        } else {
            for (i, ch) in MixerChannel.allCases.enumerated() {
                let current = store.mixer.mixes[.creator]?.channels[ch]?.muted ?? false
                let m0 = masks[0] & (1 << i) != 0, m1 = masks[1] & (1 << i) != 0
                guard m0 != current || m1 != current else { continue }
                // One of the mixes was toggled on the device: that is the new state for both.
                let muted = !current
                for b in MixBus.allCases { store.mixer.mixes[b, default: MixState()].channels[ch, default: ChannelState()].muted = muted }
                changed = true
                if ch == .mic { micChanged = true }
            }
            // Re-align the two mixes on the device.
            if changed || masks[0] != masks[1] { controller?.send(AXProtocol.mixerMutes(muteMasks())) }
        }
        if micChanged { applyMic() }
    }

    /// Mute state reported by the hardware for a knob-driven channel.
    func mirrorKnobMute(_ index: Int, _ muted: Bool) {
        guard index < MixerChannel.allCases.count else { return }
        let ch = MixerChannel.allCases[index]
        let buses: [MixBus] = [store.mixer.dualMix ? store.mixer.activeMix : .creator]
        var changed = false
        for b in buses where store.mixer.mixes[b]?.channels[ch]?.muted != muted {
            store.mixer.mixes[b, default: MixState()].channels[ch, default: ChannelState()].muted = muted
            changed = true
        }
        if changed && ch == .mic { applyMic() }
    }

    /// 12 meter samples: assumed 6 per mix in channel order.
    /// Raw sample → 0…100, as AxCorePrivate::levelScaleAndEmit: dB = 20·log10(√2·s/32767), clamped to −60…0.
    static func meterPercent(_ sample: Int) -> Int {
        let db = max(-60, min(0, 20 * log10(max(1e-9, sqrt(2) * Double(sample) / 32767))))
        return Int((db + 60) * 100 / 60 + 0.5)
    }

    /// Gain applied to a meter for each channel volume step 0…20 (Q15), from the reference SDK.
    static let meterGain: [Int] = [0, 3, 32, 103, 327, 582, 1304, 1842, 2920, 4125, 5827, 7335, 9235, 11626, 14636, 16422, 18426, 20675, 23197, 26028, 29204]
    /// Below this level (after the fader) a source is considered silent: hides cable hum on unused inputs.
    static let meterFloorDB = -48.0
    /// Latest mic input level in dBFS (after the gain, before effects): used to calibrate the noise gate.
    private(set) var micInputDB: Double = -120

    /// Meters per mix: six left/right pairs in the order Mic, Line In, Console, System, Game, Chat (verified on hardware).
    /// - Mic: real input level (after the mic gain, before the fader), so even a quiet voice shows.
    /// - Other channels: level after the channel fader, as the reference app, ignoring noise below −48 dB.
    /// A muted channel shows nothing.
    func updateMeters(_ raw: [Int]) {
        guard raw.count >= 12 else { return }
        micInputDB = 20 * log10(max(1e-9, sqrt(2) * Double(max(raw[0], raw[1])) / 32767))
        duckingTick()
        for bus in MixBus.allCases {
            let mix = store.mixer.mixes[store.mixer.dualMix ? bus : .creator] ?? MixState()
            var m: [MixerChannel: Int] = [:]
            for (k, ch) in MixerChannel.allCases.enumerated() {
                let c = mix.channels[ch] ?? ChannelState()
                let peak = max(raw[2 * k], raw[2 * k + 1])
                if c.muted || mix.muted { m[ch] = 0; continue }
                if ch == .mic && coughs(bus == .creator ? .headphones : .stream) { m[ch] = 0; continue }
                if ch == .mic {
                    // With the noise gate on, nothing below its threshold reaches the mix: show it as silence.
                    let gate = store.dsp
                    let db = 20 * log10(max(1e-9, sqrt(2) * Double(peak) / 32767))
                    m[ch] = gate.noiseGateEnabled && db < gate.noiseGate.closeThreshold ? 0 : Self.meterPercent(peak)
                    continue
                }
                let sample = (peak * Self.meterGain[max(0, min(20, Self.hw(c.level * mix.level / 100)))]) >> 15
                let db = 20 * log10(max(1e-9, sqrt(2) * Double(sample) / 32767))
                m[ch] = db < Self.meterFloorDB ? 0 : Self.meterPercent(sample)
            }
            meters[bus] = m
            outputMeters[bus] = m.values.max() ?? 0
        }
    }

    func readBackFromDevice() async {
        guard let c = controller, let state = await c.readMixer() else { return }
        for bus in MixBus.allCases {
            for (i, ch) in MixerChannel.allCases.enumerated() {
                store.mixer.mixes[bus, default: MixState()].channels[ch, default: ChannelState()].level = Self.ui(state.volumes[bus.rawValue][i])
                store.mixer.mixes[bus, default: MixState()].channels[ch, default: ChannelState()].muted = state.mutes[bus.rawValue] & (1 << i) != 0
            }
        }
    }

    func saveToDevice() { controller?.send(AXProtocol.saveToFlash()) }
}

/// Live input levels (0…100) shared with views rendered outside the environment (panel frames).
@MainActor
final class LevelMeters: ObservableObject {
    static let shared = LevelMeters()
    @Published var values: [MixBus: [MixerChannel: Int]] = [:]
}
