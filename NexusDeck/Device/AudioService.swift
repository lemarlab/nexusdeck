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
            if bus == .audience && p.obsTracks {
                // OBS tracks mode: only the Line In, at full level (its knob is applied to the OBS copy).
                c.send(AXProtocol.mixerVolumes(mixer: 1, values: [0, AXProtocol.mixerVolumeMax, 0, 0, 0, 0]))
                continue
            }
            let mix = p.mixes[p.dualMix ? bus : .creator] ?? MixState()
            let values = MixerChannel.allCases.map { ch -> Int in
                let s = mix.channels[ch] ?? ChannelState()
                return Self.hw(s.level * mix.level / 100)
            }
            c.send(AXProtocol.mixerVolumes(mixer: bus.rawValue, values: values))
        }
        c.send(AXProtocol.mixerMutes(muteMasks()))
        c.send(AXProtocol.knobControl(mixer: p.dualMix && !p.obsTracks ? p.activeMix.rawValue : 0, linked: !p.dualMix && !p.obsTracks))
        // The monitor overrides the mic volume in some mixes: re-apply it after the volumes.
        applyMic()
        if ducked || duckAmount > 0 { applyDucking(force: true) } else { sentDuckSteps = [:] }
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
            // NexusDeck voice changer on: the clean mic is replaced (it comes back filtered on the Chat channel).
            if (bus == .creator ? !hearsMic : !micInStream) || store.dsp.appVoiceActive { m |= 1 }
            if bus == .audience && p.obsTracks { m = 0x3F & ~(1 << 1) }
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
    /// Current amount of ducking, 0 (full volume) … 1 (fully lowered): moves gradually for the fades.
    @Published private(set) var duckAmount: Double = 0
    private var lastSpeech = Date.distantPast
    private var fadeTimer: Timer?
    private var lastFadeTick = Date()
    /// Last volume step written per "bus.channel", so a fade only sends the steps that change.
    private var sentDuckSteps: [String: Int] = [:]

    private func duckingTick() {
        let d = store.mixer.ducking
        guard d.enabled else { if ducked { setDucked(false) }; return }
        if micInputDB > d.thresholdDB && micInStream { lastSpeech = Date() }
        let should = Date().timeIntervalSince(lastSpeech) * 1000 < d.releaseMs
        if should != ducked { setDucked(should) }
    }

    /// Lowered volume step whose gain is `reduction` dB below the one of `base` (gain table of the device).
    private static func duckedStep(_ base: Int, _ reductionDB: Double) -> Int {
        guard base > 0, reductionDB > 0.01 else { return base }
        let target = Double(meterGain[min(20, base)]) * pow(10, -reductionDB / 20)
        return (0...base).last { Double(meterGain[$0]) <= target } ?? 0
    }

    private func setDucked(_ on: Bool) {
        ducked = on
        startFade()
    }

    /// Fades the ducked channels down (fade out) or back up (fade in) over the chosen times.
    private func startFade() {
        guard fadeTimer == nil else { return }
        lastFadeTick = Date()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeTick() }
        }
    }

    private func fadeTick() {
        let d = store.mixer.ducking
        let now = Date()
        let dt = now.timeIntervalSince(lastFadeTick) * 1000
        lastFadeTick = now
        let target: Double = ducked && d.enabled ? 1 : 0
        let duration = max(1, target > duckAmount ? d.fadeOutMs : d.fadeInMs)
        let step = dt / duration
        duckAmount = target > duckAmount ? min(target, duckAmount + step) : max(target, duckAmount - step)
        applyDucking()
        if duckAmount == target { fadeTimer?.invalidate(); fadeTimer = nil }
    }

    /// Writes the (possibly lowered) volumes of the ducked channels. Only changed steps are sent, unless forced
    /// (after the mixer volumes were rewritten).
    func applyDucking(force: Bool = false) {
        guard let c = controller else { return }
        let p = store.mixer
        let d = p.ducking
        var buses: [MixBus] = d.streamOnly ? [.audience] : (p.dualMix ? MixBus.allCases : [.creator, .audience])
        if p.obsTracks { buses = [.creator] }
        if force { sentDuckSteps = [:] }
        var cmds: [AXProtocol.Command] = []
        for name in d.channels {
            guard let ch = MixerChannel(rawValue: name), ch != .mic, let index = MixerChannel.allCases.firstIndex(of: ch) else { continue }
            for b in buses {
                let mix = p.mixes[p.dualMix ? b : .creator] ?? MixState()
                let base = Self.hw((mix.channels[ch]?.level ?? 50) * mix.level / 100)
                let value = Self.duckedStep(base, d.enabled ? d.reductionDB * duckAmount : 0)
                let key = "\(b.rawValue).\(ch.rawValue)"
                guard sentDuckSteps[key] != value else { continue }
                sentDuckSteps[key] = value
                var cmd = AXProtocol.mixerVolume(mixer: b.rawValue, channel: index, value: value)
                cmd.preDelayMs = 0
                cmds.append(cmd)
            }
        }
        if !cmds.isEmpty { c.sendInOrder(cmds) }
    }

    /// Gain factor of the OBS copy of a ducked channel (the copies are lowered like the mixer).
    func duckFactor(_ ch: MixerChannel) -> Float {
        let d = store.mixer.ducking
        guard d.enabled, duckAmount > 0, d.channels.contains(ch.rawValue) else { return 1 }
        return Float(pow(10, -d.reductionDB * duckAmount / 20))
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

    /// Reverb and echo only (fast: the toggles and sliders of these two effects send just this).
    func applyReverb() {
        guard let c = controller else { return }
        let d = store.dsp
        let anyReverb = d.reverbEnabled || d.echoEnabled
        var master = AXProtocol.reverbMaster(anyReverb); master.preDelayMs = 0
        var cmds = [master]
        if anyReverb {
            let r = d.reverbPresets[min(d.reverbPresetIndex, d.reverbPresets.count - 1)]
            let mask: UInt8 = (d.reverbEnabled ? 1 : 0) | (d.echoEnabled ? 2 : 0)
            var cmd = AXProtocol.reverb(r, echo: d.echo, enabled: mask); cmd.preDelayMs = 0
            cmds.append(cmd)
        }
        c.sendInOrder(cmds)
    }

    /// Voice changer: gain of the filtered voice sent back to the mixer (heard in headphones / on stream).
    var voiceReturnGain: Float {
        guard store.dsp.appVoiceActive else { return 0 }
        return hearsMic || micInStream ? 1 : 0
    }

    func toggleAppVoice(_ voice: Int? = nil) {
        if let voice, voice != store.dsp.appVoice { store.dsp.appVoice = voice; store.dsp.appVoiceOn = true }
        else { store.dsp.appVoiceOn.toggle() }
        applyMic()
    }

    func applyDSP() {
        guard let c = controller else { return }
        let d = store.dsp
        applyEQ()
        applyGate()
        applyCompressor()
        applyReverb()
        c.send(AXProtocol.voiceChanger(d.voiceChanger.rawValue))
    }

    // Single effects: the editor sends only the block that changed, right away.

    func applyEQ() {
        guard let c = controller else { return }
        let d = store.dsp
        var cmds = AXProtocol.eqEnable(d.eqEnabled)
        if d.eqEnabled { cmds += d.currentEQ.enumerated().map { AXProtocol.eqBand(index: $0.offset, $0.element) } }
        c.sendInOrder(cmds.map { var x = $0; x.preDelayMs = 0; return x })
    }

    func applyGate() {
        guard let c = controller else { return }
        let d = store.dsp
        var cmds = [AXProtocol.noiseGateEnable(d.noiseGateEnabled)]
        if d.noiseGateEnabled { cmds.append(AXProtocol.noiseGate(d.noiseGate)) }
        c.sendInOrder(cmds.map { var x = $0; x.preDelayMs = 0; return x })
    }

    func applyCompressor() {
        guard let c = controller else { return }
        let d = store.dsp
        var cmds = [AXProtocol.compressorEnable(d.compressorEnabled)]
        if d.compressorEnabled {
            let comp = d.compressorPresets[min(d.compressorPresetIndex, d.compressorPresets.count - 1)]
            cmds.append(AXProtocol.compressor(d.compressorPresets[0], comp, makeup: d.makeupGain))
        }
        c.sendInOrder(cmds.map { var x = $0; x.preDelayMs = 0; return x })
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
    var ledTask: Task<Void, Never>?

    enum LEDGroup: Hashable { case knobs, aura, buttons }
    var pendingLEDs: Set<LEDGroup> = []
    var lastSentLEDs: DeviceSettings?
    /// Last state written to each knob ring (per-knob colors), to send only what changed.
    var lastRings: [String]?

    /// Debounced: only groups whose settings changed are sent, once the user stops dragging.
    /// Start-up: no LED is lit until the volumes are set; then keys, rings and strip are restored in one go.
    var ringsKeepColors = false

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
        var hwBuses: [MixBus] = store.mixer.dualMix ? [bus] : MixBus.allCases
        if store.mixer.obsTracks { hwBuses.removeAll { $0 == .audience } }
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

    func setOBSTracks(_ on: Bool) {
        store.mixer.obsTracks = on
        if on { store.mixer.activeMix = .creator }
        applyMixer()
    }

    /// Gain (0…1) of a channel's OBS copy: follows its knob, mute and stream routing like the mixer does.
    func captureGain(_ ch: MixerChannel) -> Float {
        let p = store.mixer
        let mix = p.mixes[p.dualMix && !p.obsTracks ? .audience : .creator] ?? MixState()
        let c = mix.channels[ch] ?? ChannelState()
        if c.muted || mix.muted || (!p.obsTracks && !p.isRouted(ch, to: .stream)) { return 0 }
        return Float(Self.meterGain[min(20, Self.hw(c.level * mix.level / 100))]) / 32768 * duckFactor(ch)
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
    private var lastMeterPublish = Date.distantPast

    func updateMeters(_ raw: [Int]) {
        guard raw.count >= 12 else { return }
        micInputDB = 20 * log10(max(1e-9, sqrt(2) * Double(max(raw[0], raw[1])) / 32767))
        duckingTick()
        // The UI meters refresh about 15 times a second (every publish redraws the views that show them).
        let now = Date()
        guard now.timeIntervalSince(lastMeterPublish) >= 1.0 / 15 else { return }
        lastMeterPublish = now
        var newMeters = meters
        var newOut = outputMeters
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
            newMeters[bus] = m
            newOut[bus] = m.values.max() ?? 0
        }
        // One publish for both mixes (and none when nothing moved).
        if newMeters != meters { meters = newMeters }
        if newOut != outputMeters { outputMeters = newOut }
    }

    /// Startup check: reads the volumes back from the mixer and, if they differ from the profile (the device
    /// can drop writes while it is still waking up, e.g. after quitting and reopening quickly), sends the
    /// whole state again. Returns true when the mixer matches.
    @discardableResult
    func verifyDeviceState() async -> Bool {
        guard let c = controller else { return false }
        // Knob ring mode (config1): when the mixer is reset it lights every ring at full instead of the level.
        let k = AXProtocol.ledEffect(mode: store.library.device.ledKnob.mode.rawValue, peak: store.library.device.ledKnob.peak)
        guard let reply = await c.transact(AXProtocol.readConfig1()), reply.count > 4 else { return false }
        var cfg = reply[4] & ~0x0E
        if k.sdk == 0 { cfg = reply[4] & ~0x06 } else if k.sdk == 7 { cfg |= 0x0A } else { cfg |= 0x0C }
        if cfg != reply[4] {
            SDKHost.shared.debugLog("Startup check: ring mode \(String(reply[4], radix: 16)) → \(String(cfg, radix: 16))")
            return false
        }
        guard let state = await c.readMixer() else { return false }
        let p = store.mixer
        var buses: [MixBus] = p.dualMix ? MixBus.allCases : [.creator]
        if p.obsTracks { buses = [.creator] }
        for bus in buses {
            let mix = p.mixes[p.dualMix ? bus : .creator] ?? MixState()
            for (i, ch) in MixerChannel.allCases.enumerated() where ch != .mic {
                // Ducked channels are lowered on purpose.
                if p.ducking.enabled && duckAmount > 0 && p.ducking.channels.contains(ch.rawValue) { continue }
                let want = Self.hw((mix.channels[ch]?.level ?? 50) * mix.level / 100)
                if abs(state.volumes[bus.rawValue][i] - want) > 1 { return false }
            }
        }
        return true
    }


}

/// Live input levels (0…100) shared with views rendered outside the environment (panel frames).
@MainActor
final class LevelMeters: ObservableObject {
    static let shared = LevelMeters()
    @Published var values: [MixBus: [MixerChannel: Int]] = [:]
}
