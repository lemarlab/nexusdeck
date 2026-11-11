import Foundation
import Combine

/// Keeps the hardware mixer, mic DSP and device settings in sync with the active profiles.
@MainActor
final class AudioService: ObservableObject {
    @Published var meters: [MixBus: [MixerChannel: Int]] = [:] { didSet { LevelMeters.shared.values = meters } }
    @Published var outputMeters: [MixBus: Int] = [:]

    let store: ProfileStore
    let ledManager = LEDManager()
    var controller: AXController? {
        didSet {
            // Attach / detach: the next writes must reach the device even if they look unchanged.
            controller?.invalidateWriteCache()
            if controller == nil { ledManager.detach() }
        }
    }

    init(store: ProfileStore) {
        self.store = store
        ledManager.service = self
    }

    /// Measured 2026-11-11: Audience→USB path (Line In) sits ~7.5 dB below the Creator mix for the same source,
    /// so the OBS copy needs this compensation to match headphone balance.
    static let lineInOBSCompensationDB: Double = 7.5
    static let lineInOBSCompensation: Float = Float(pow(10, 7.5 / 20.0))
    static func hw(_ level: Int) -> Int { Int((Double(level) / 100 * Double(AXProtocol.mixerVolumeMax)).rounded()) }
    static func ui(_ hw: Int) -> Int { min(100, hw * 100 / AXProtocol.mixerVolumeMax) }

    // MARK: Full sync

    func applyAll() {
        updateScreamGuard()
        applyMixer()
        applyMic()
        applyDSP()
        applyDevice()
        ledManager.update()
    }

    func applyMixer() {
        guard let c = controller else { return }
        let p = store.mixer
        // The knobs drive the Creator mix, unlinked: send it before the volumes so a firmware reset does not
        // leave them on the Audience bus.
        c.send(AXProtocol.knobControl(mixer: 0, linked: false))
        for bus in MixBus.allCases {
            if bus == .audience {
                // Audience is an internal Line In bus: the physical Line In at unity (its knob is applied to
                // the OBS copy), every other channel silent through the volume registers, never the mute bits.
                c.send(Self.audienceRow())
                continue
            }
            let mix = p.mixes[.creator] ?? MixState()
            let values = MixerChannel.allCases.map { ch -> Int in
                let s = mix.channels[ch] ?? ChannelState()
                return Self.hw(s.level * mix.level / 100)
            }
            c.send(AXProtocol.mixerVolumes(mixer: bus.rawValue, values: values))
        }
        c.send(AXProtocol.mixerMutes(muteMasks()))
        // The monitor overrides the mic volume in some mixes: re-apply it after the volumes.
        applyMic()
        if ducked || duckAmount > 0 { applyDucking(force: true) } else { sentDuckSteps = [:] }
    }

    /// Audience is an internal Line In bus: the physical Line In at unity, every other channel at 0
    /// (through the volume registers). Sent on a full mixer sync (attach / resync): the controller skips it
    /// when the payload did not change.
    static func audienceRow() -> AXProtocol.Command {
        AXProtocol.mixerVolumes(mixer: 1, values: [0, AXProtocol.mixerVolumeMax, 0, 0, 0, 0])
    }

    // MARK: Mic state per output
    //
    // Outputs: headphones = Creator mix, chat = Chat Mic mix (verified on the device:
    // it carries the mic only; bit0 of the third mute byte mutes it). The Audience mix is internal (Line In).

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
        case .chat: return out == .chat
        }
    }

    /// The mic is heard in the headphones only with the monitor on and the mic not muted.
    private var hearsMic: Bool {
        store.mixer.micMonitor && !micMuted(.creator) && store.mixer.isRouted(.mic, to: .headphones) && !coughs(.headphones)
    }

    func muteMasks() -> [UInt8] {
        let p = store.mixer
        let mix = p.mixes[.creator] ?? MixState()
        var creator: UInt8 = 0
        var audience: UInt8 = 0
        // Mute bits = real user mutes only (channel/bus mute and the routing matrix). Software voice,
        // scream protection and OBS tracks no longer touch them: the processed voice is muted in the bridge.
        for (i, ch) in MixerChannel.allCases.enumerated() where ch != .mic {
            let muted = mix.muted || (mix.channels[ch]?.muted ?? false)
            if muted || !p.isRouted(ch, to: .headphones) { creator |= 1 << i }
            if muted { audience |= 1 << i }
        }
        // Monitor off: the firmware needs the mic bit in Creator to keep it out of the headphones.
        if !hearsMic { creator |= 1 }
        // The Audience bus carries no mic: its bit mirrors the user's mic mute only.
        if micMuted(.creator) { audience |= 1 }
        var masks: [UInt8] = [creator, audience]
        masks.append(micInChatMix ? 0 : 1)
        return masks
    }

    /// Chat Mic output: muted on its own, by the "all" mute, by routing or by the cough key.
    private var micInChatMix: Bool {
        let p = store.mixer
        return !p.chatMicMuted && !micMuted(.creator) && p.isRouted(.mic, to: .chat) && !coughs(.chat)
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
            let muted = !(micMuted(.creator) && store.mixer.chatMicMuted)
            store.mixer.mixes[.creator, default: MixState()].channels[.mic, default: ChannelState()].muted = muted
            store.mixer.chatMicMuted = muted
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
    private var lastDuckWrite = Date.distantPast
    /// Last volume step written per "bus.channel", so a fade only sends the steps that change.
    private var sentDuckSteps: [String: Int] = [:]

    private func duckingTick() {
        let d = store.mixer.ducking
        guard d.enabled else { if ducked { setDucked(false) }; return }
        if micInputDB > d.thresholdDB && !micMuted(.creator) { lastSpeech = Date() }
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
        // Every volume write makes the mixer redraw all the knob rings: at most one fade step every 250 ms
        // (the Mic ring drawn by the app needs that gap to be written again after it), the last one always.
        if duckAmount == target || now.timeIntervalSince(lastDuckWrite) >= 0.3 {
            lastDuckWrite = now
            applyDucking()
        }
        if duckAmount == target { fadeTimer?.invalidate(); fadeTimer = nil }
    }

    /// Writes the (possibly lowered) volumes of the ducked channels. Only changed steps are sent, unless forced
    /// (after the mixer volumes were rewritten).
    func applyDucking(force: Bool = false) {
        guard let c = controller else { return }
        let p = store.mixer
        let d = p.ducking
        // Ducking only touches the Creator mix: the Audience bus is a fixed Line In bus.
        let buses: [MixBus] = [.creator]
        if force { sentDuckSteps = [:] }
        var cmds: [AXProtocol.Command] = []
        for name in d.channels {
            // Software ducking: the channels coming from the Mac are lowered in the audio bridge, not here.
            guard let ch = MixerChannel(rawValue: name), ch != .mic, !(softDucking && ch.fromMac), let index = MixerChannel.allCases.firstIndex(of: ch) else { continue }
            for b in buses {
                let mix = p.mixes[.creator] ?? MixState()
                let base = Self.hw((mix.channels[ch]?.level ?? 50) * mix.level / 100)
                // With the voice going through NexusDeck the Mac channels jump straight to their target (two
                // writes per phrase instead of a fade): their gain is applied in the bridge, sample by sample.
                let amount: Double = softDucking ? (ducked && d.enabled ? 1 : 0) : duckAmount
                let value = Self.duckedStep(base, d.enabled ? d.reductionDB * amount : 0)
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

    /// Voice priority in software while the voice goes through NexusDeck (voice changer or cleanup): the mixer
    /// volume writes of a fade would fight with the bridge's voice processing, so the Mac channels (System, Game,
    /// Chat) are lowered in the audio bridge instead and their rings keep the set volume.
    var softDucking: Bool { store.dsp.softwareVoiceActive }

    /// Gain of a Mac channel in the audio bridge (software ducking).
    func bridgeDuckFactor(_ ch: MixerChannel) -> Float { softDucking ? duckFactor(ch) : 1 }

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
        // bit0 phantom power, bit1 = Creator mix gets the mic WITH effects (always on), bit2 = Audience mix:
        // cleared, the Audience bus is Line-In-only now. bit3 = Chat Mic with effects (setting),
        // bit4 = 6.3 mm jack input.
        var cfg: UInt8 = (p.phantom48V ? 0x01 : 0) | 0x02
        if store.library.device.chatMicWithEffects { cfg |= 0x08 }
        if p.micInput == .jack63 { cfg |= 0x10 }
        c.send(AXProtocol.micConfig(cfg))
        // Monitor (hearing your own mic in the headphones), verified on the device (PROTOCOL.md §Mic routing):
        // - the headphones listen to the Creator mix (register 0x15 = 0) and to the Chat Mic mix;
        // - register 0x22 = 0x12 restores the Chat Mic → headphones path (monitor on); 0x22 = 0x31 cuts it
        //   (hardware-verified, read back as 0x33) while the Chat Mic USB output keeps the voice;
        // - host writes of the mic bit in 0x12 are ignored: the firmware owns the Mic knob mute in Audience.
        // Monitor off (incl. a muted/routed-away mic, as enableMonitor in the reference app) = the Creator mic
        // bit in the mute masks + 0x22 = 0x31. The mic ring is drawn by the firmware.
        c.sendInOrder([AXProtocol.micMonitor(mixer: hearsMic ? 2 : 1, sync: hearsMic ? 1 : 3),
                       AXProtocol.headphoneSource(0),
                       AXProtocol.mixerMutes(muteMasks())].map { var x = $0; x.preDelayMs = 0; return x })
        c.send(AXProtocol.preampGain(MicGain.register(effectiveGainDB)))
        ledManager.update()  // also when nothing was written (cleanup switched on or off)
    }

    // MARK: Scream protection

    /// Mic peak straight from the audio (set by the app: the bridge).
    var micPeakSource: () -> Float = { 0 }
    /// Applies the gain of the processed voice in the bridge (0 = muted by the scream guard).
    var voiceGainSink: (Float) -> Void = { _ in }
    @Published private(set) var screaming = false
    private var screamMuted: Bool { screaming && store.mixer.screamGuard.mode == .mute }
    private var lastScream = Date.distantPast
    private var screamTimer: Timer?

    /// Mic gain actually sent: lowered while the protection is on in "lower" mode.
    private var effectiveGainDB: Int {
        let p = store.mixer
        guard screaming, p.screamGuard.mode == .lower else { return p.currentGainDB }
        return max(0, p.currentGainDB - Int(p.screamGuard.reductionDB.rounded()))
    }

    /// Starts or stops watching the mic (every 20 ms) for the scream protection.
    func updateScreamGuard() {
        if store.mixer.screamGuard.enabled {
            guard screamTimer == nil else { return }
            _ = micPeakSource()
            screamTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.screamTick() }
            }
        } else {
            screamTimer?.invalidate(); screamTimer = nil
            if screaming { setScreaming(false) }
        }
    }

    private func screamTick() {
        let g = store.mixer.screamGuard
        guard g.enabled, controller != nil else { if screaming { setScreaming(false) }; return }
        // Fast path: peak of the audio itself. The mixer meter (input, before any mute) keeps the level known
        // while the mic is muted. While lowered, the level is measured lower by the reduction: added back.
        let peakDB = 20 * log10(Double(max(micPeakSource(), 1e-9)))
        let applied = Double(store.mixer.currentGainDB - effectiveGainDB)
        let level = max(screamMuted ? -120 : peakDB, micInputDB) + applied
        if level > g.thresholdDB { lastScream = Date() }
        let should = Date().timeIntervalSince(lastScream) * 1000 < g.releaseMs
        if should != screaming { setScreaming(should) }
    }

    private func setScreaming(_ on: Bool) {
        screaming = on
        // "mute" mode attenuates the processed voice in the bridge (the hardware mic has no mute bit of ours).
        voiceGainSink(screamMuted ? 0 : 1)
        guard let c = controller else { return }
        // Coming back the preamp gain is restored (the mode may have changed meanwhile).
        if !on || store.mixer.screamGuard.mode == .lower { c.send(AXProtocol.preampGain(MicGain.register(effectiveGainDB))) }
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

    /// Voice changer: gain of the filtered voice for a future monitor return. Currently inert: the bridge keeps
    /// the processed voice out of the mixer's Chat channel (no headphone monitoring).
    var voiceReturnGain: Float {
        guard store.dsp.softwareVoiceActive else { return 0 }
        return hearsMic ? 1 : 0
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
        // Line Out source: Creator Mix (Chat Mic only as the extra option; old "Audience" maps to Creator).
        c.send(AXProtocol.lineOutSource(s.lineOutSource == 2 ? 2 : 0))
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

    /// Current LED state (function-key colours, strip override). The knob rings, the Mic ring included, are
    /// drawn by the firmware.
    func ledAudioState() -> LEDAudioState {
        var state = LEDAudioState()
        state.functionKeyColors = functionKeyColors()
        state.auraOverride = auraOverride
        return state
    }

    // MARK: Edits from UI / actions

    /// A volume write unmutes the channel on the device (verified for the mic): re-send the mutes after it.
    func reassertMutes() {
        controller?.send(AXProtocol.mixerMutes(muteMasks()))
    }

    func setLevel(_ ch: MixerChannel, bus: MixBus, _ level: Int) {
        let l = max(0, min(100, level))
        store.mixer.mixes[.creator, default: MixState()].channels[ch, default: ChannelState()].level = l
        let mix = store.mixer.mixes[.creator] ?? MixState()
        controller?.send(AXProtocol.mixerVolume(mixer: MixBus.creator.rawValue, channel: MixerChannel.allCases.firstIndex(of: ch)!,
                                                value: Self.hw(l * mix.level / 100)))
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

    /// Gain (0…1) of a channel's OBS copy: follows its knob and mute like the mixer does.
    func captureGain(_ ch: MixerChannel) -> Float {
        let p = store.mixer
        let mix = p.mixes[.creator] ?? MixState()
        let c = mix.channels[ch] ?? ChannelState()
        if c.muted || mix.muted { return 0 }
        return Float(Self.meterGain[min(20, Self.hw(c.level * mix.level / 100))]) / 32768 * duckFactor(ch)
    }

    /// Absolute knob value 0...20 reported by hardware knob i.
    func knobMoved(_ index: Int, hwValue: Int) {
        guard index < MixerChannel.allCases.count else { return }
        let ch = MixerChannel.allCases[index]
        let level = Self.ui(hwValue)
        store.mixer.mixes[.creator, default: MixState()].channels[ch, default: ChannelState()].level = level
        // The firmware has already applied the knob (volume, ring, and for the mic its own audience copy): no
        // HID write here, a register write would make it reset and redraw the rings. The knobs drive the
        // Creator mix unlinked, so mixer 1 cannot change and nothing in the app follows the mic fader.
    }

    /// A mixer knob was pressed: its channel mute flips in the Creator mix.
    func knobToggledMute(_ index: Int) {
        guard index < MixerChannel.allCases.count else { return }
        let ch = MixerChannel.allCases[index]
        if ch == .mic { toggleMicMute(); return }
        let muted = !(store.mixer.mixes[.creator]?.channels[ch]?.muted ?? false)
        store.mixer.mixes[.creator, default: MixState()].channels[ch, default: ChannelState()].muted = muted
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
        // Only the Creator mix is shown: the Audience bus is internal (Line In only).
        for bus in [MixBus.creator] {
            let mix = store.mixer.mixes[.creator] ?? MixState()
            var m: [MixerChannel: Int] = [:]
            for (k, ch) in MixerChannel.allCases.enumerated() {
                let c = mix.channels[ch] ?? ChannelState()
                let peak = max(raw[2 * k], raw[2 * k + 1])
                if c.muted || mix.muted { m[ch] = 0; continue }
                if ch == .mic && coughs(.headphones) { m[ch] = 0; continue }
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
        let mix = p.mixes[.creator] ?? MixState()
        for (i, ch) in MixerChannel.allCases.enumerated() where ch != .mic {
            // Ducked channels are lowered on purpose.
            if p.ducking.enabled && duckAmount > 0 && p.ducking.channels.contains(ch.rawValue) { continue }
            let want = Self.hw((mix.channels[ch]?.level ?? 50) * mix.level / 100)
            if abs(state.volumes[MixBus.creator.rawValue][i] - want) > 1 { return false }
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
