import Foundation

/// LEDs: knob rings, function keys and the ambient strip.
extension AudioService {
    /// Quit: every LED off (strip, function keys, rings).
    func allLEDsOff() {
        guard let c = controller else { return }
        // The strip goes last and twice (like sendAura): right after the panel images its first write can be dropped.
        var cmds: [AXProtocol.Command] = []
        for i in 0..<4 { cmds.append(AXProtocol.functionKeyLED(index: i, on: false, r: 0, g: 0, b: 0)) }
        cmds.append(AXProtocol.knobRings(sdkMode: 0, r: 0, g: 0, b: 0, speed: 0))
        let stripOff = AXProtocol.auraStrip(sdkMode: 0, r: 0, g: 0, b: 0, speed: 0)
        cmds += [stripOff, stripOff]
        for var cmd in cmds { cmd.preDelayMs = 120; c.sendAndWait(cmd, timeout: 0.6) }
    }

    /// Re-enables the level display of the knob rings (config1), the way the LED setup does.
    func restoreRingLevelMode() async {
        guard let c = controller else { return }
        let k = AXProtocol.ledEffect(mode: store.library.device.ledKnob.mode.rawValue, peak: store.library.device.ledKnob.peak)
        guard let reply = await c.transact(AXProtocol.readConfig1()), reply.count > 4 else { return }
        var cfg = reply[4] & ~0x0E
        if k.sdk == 0 { cfg = reply[4] & ~0x06 } else if k.sdk == 7 { cfg |= 0x0A } else { cfg |= 0x0C }
        var cmd = AXProtocol.config1(cfg); cmd.preDelayMs = 0
        c.sendInOrder([cmd])
    }

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
            // Start-up: everything waits for the final restore.
            if self.ringsKeepColors { return }
            let groups = self.pendingLEDs
            self.pendingLEDs.removeAll()
            let s = self.store.library.device
            // One sequence, in the same order as at quit: function keys 1-4, knob rings, then the strip.
            var seq: [AXProtocol.Command] = groups.contains(.buttons) ? self.functionKeyCommands() : []

            if groups.contains(.knobs) && self.ringsKeepColors {
                await self.restoreRingLevelMode()
            } else if groups.contains(.knobs) {
                let k = AXProtocol.ledEffect(mode: s.ledKnob.mode.rawValue, peak: s.ledKnob.peak)
                // Rewriting config1 resets the rings for a moment: only when the effect really changes.
                var ringConfig: UInt8?
                if let reply = await c.transact(AXProtocol.readConfig1()), reply.count > 4 {
                    var cfg = reply[4] & ~0x0E
                    if k.sdk == 0 { cfg = reply[4] & ~0x06 } else if k.sdk == 7 { cfg |= 0x0A } else { cfg |= 0x0C }
                    if cfg != reply[4] { seq.append(AXProtocol.config1(cfg)); self.lastRings = nil }
                    ringConfig = cfg
                }
                // Rings and the level mode go out in one burst, without the LED pre-delay: a ring write leaves the
                // ring fully lit until config1 is set again, so the gap between them must be as short as possible.
                var burst: [AXProtocol.Command] = []
                // The mixer needs a short pause between LED writes (with none, only the last ring is taken).
                func add(_ cmd: AXProtocol.Command) {
                    var c = cmd; c.preDelayMs = 250; burst.append(c)
                    // Each ring is switched back to the level display right after its write, so it never shows
                    // fully lit: the rings come up one after the other, left to right.
                    if k.sdk != 0, let cfg = ringConfig {
                        var lv = AXProtocol.config1(cfg); lv.preDelayMs = 120; burst.append(lv)
                    }
                }
                let speed = k.speed ? UInt8(s.ledKnob.speed) : 0
                if s.ledKnob.colorSource == .perItem && s.ledKnob.mode.usesColor {
                    var sent = self.lastRings ?? [String](repeating: "", count: 6)
                    for i in 0..<6 {
                        let kc = Self.rgb(s.ledKnob.itemColors[i], brightness: s.ledKnob.brightness)
                        let sig = "\(k.sdk)-\(speed)-\(kc.0)-\(kc.1)-\(kc.2)"
                        // Only the rings that changed are rewritten.
                        if sent[i] == sig { continue }
                        add(AXProtocol.knobRing(i, sdkMode: k.sdk, r: kc.0, g: kc.1, b: kc.2, speed: speed))
                        sent[i] = sig
                    }
                    self.lastRings = sent
                } else {
                    let kc = k.white ? (UInt8(255), UInt8(255), UInt8(255)) : Self.rgb(s.ledKnob.colorHex, brightness: s.ledKnob.brightness)
                    add(AXProtocol.knobRings(sdkMode: k.sdk, r: kc.0, g: kc.1, b: kc.2, speed: speed))
                    self.lastRings = nil
                }
                seq += burst
            }
            if groups.contains(.aura) { seq += self.auraCommands(self.auraOverride ?? s.ledAura) }
            // The level display (config1) above puts the Mic ring back to "muted": draw it again.
            self.lastMicRing = nil
            if let mic = self.micRingCommand() { seq.append(mic); self.lastMicRing = mic.bytes }
            if !seq.isEmpty { c.sendInOrder(seq) }
        }
    }

    /// Function key LEDs: off, the key's own background color, or one custom color.
    func sendFunctionKeyLEDs() async {
        guard let c = controller, !ringsKeepColors else { return }
        c.sendInOrder(functionKeyCommands())
    }

    /// Function keys 1-4, in order.
    func functionKeyCommands() -> [AXProtocol.Command] {
        let s = store.library.device
        var cmds: [AXProtocol.Command] = []
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
            cmds.append(AXProtocol.functionKeyLED(index: i, on: on, r: col.0, g: col.1, b: col.2))
        }
        return cmds
    }

    func sendAura(_ led: LEDSetting) {
        guard let c = controller else { return }
        c.sendInOrder(auraCommands(led))
    }

    /// The strip, written twice: the mixer often drops a single strip write.
    func auraCommands(_ led: LEDSetting) -> [AXProtocol.Command] {
        let e = AXProtocol.ledEffect(mode: led.mode.rawValue, peak: led.peak)
        let col = led.mode == .off ? (UInt8(0), UInt8(0), UInt8(0)) : (e.white ? (UInt8(255), UInt8(255), UInt8(255)) : Self.rgb(led.colorHex, brightness: led.brightness))
        let cmd = AXProtocol.auraStrip(sdkMode: e.sdk, r: col.0, g: col.1, b: col.2, speed: e.speed ? UInt8(led.speed) : 0)
        return [cmd, cmd]
    }

    // MARK: Mic ring while the voice goes through NexusDeck

    /// When NexusDeck mutes the hardware mic in the stream mix, the mixer turns the Mic ring off. The ring is then
    /// drawn by NexusDeck: lit in its colour up to the Mic volume, as the level display (off only if the user muted it).
    func micRingCommand() -> AXProtocol.Command? {
        let s = store.library.device
        // The mixer ties the Mic ring to the mic mute of the Audience mix: whenever NexusDeck mutes it there
        // (voice through the Mac, scream protection, cough key, routing), the ring is drawn by the app.
        guard muteMasks().count > 1, muteMasks()[1] & 1 != 0, s.ledKnob.mode != .off, !ringsKeepColors else { return nil }
        let k = AXProtocol.ledEffect(mode: s.ledKnob.mode.rawValue, peak: s.ledKnob.peak)
        guard k.sdk != 0 else { return nil }
        let p = store.mixer
        let bus: MixBus = p.dualMix ? .audience : .creator
        let mix = p.mixes[bus] ?? MixState()
        let level = Double(mix.channels[.mic]?.level ?? 50) * Double(mix.level) / 100
        let userMuted = (mix.channels[.mic]?.muted ?? false) || mix.muted
        let length = userMuted ? 0 : UInt8(max(level > 0 ? 1 : 0, min(10, Int((level / 10).rounded()))))
        let hex = s.ledKnob.colorSource == .perItem && s.ledKnob.mode.usesColor ? s.ledKnob.itemColors[0] : s.ledKnob.colorHex
        let c = k.white ? (UInt8(255), UInt8(255), UInt8(255)) : Self.rgb(hex, brightness: s.ledKnob.brightness)
        return AXProtocol.knobRing(0, sdkMode: k.sdk, r: c.0, g: c.1, b: c.2, speed: k.speed ? UInt8(s.ledKnob.speed) : 0, length: length)
    }

    /// Draws the Mic ring again. Every mute write makes the mixer redraw it (off, as the mic is muted), so this
    /// runs after each one, shortly after the last change. When not needed, the ring goes back to the mixer.
    func applyMicRing() {
        // At most one pending redraw: a burst of writes (ducking fades) redraws it about every 120 ms.
        guard micRingTask == nil else { return }
        micRingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self else { return }
            self.micRingTask = nil
            guard let c = self.controller, !self.ringsKeepColors else { return }
            if let cmd = self.micRingCommand() {
                self.lastMicRing = cmd.bytes
                c.ringPatch = cmd.bytes
                self.startMicRingKeepAlive()
                var x = cmd; x.preDelayMs = 120
                c.sendInOrder([x])
            } else if self.lastMicRing != nil {
                self.lastMicRing = nil
                c.ringPatch = nil
                // Back to the level display drawn by the mixer.
                self.applyLEDs(force: true)
            }
        }
    }

    /// The mixer puts a ring drawn by the app back to its own display after a short while: while NexusDeck draws
    /// the Mic ring it is refreshed twice a second (same content, no visible change).
    func startMicRingKeepAlive() {
        guard micRingTimer == nil else { return }
        micRingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let c = self.controller, !self.ringsKeepColors, let cmd = self.micRingCommand() else {
                    self.controller?.ringPatch = nil
                    self.micRingTimer?.invalidate(); self.micRingTimer = nil
                    return
                }
                c.ringPatch = cmd.bytes
                c.refreshRingPatch()
            }
        }
    }
}
