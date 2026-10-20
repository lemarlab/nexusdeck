import Foundation

/// LEDs: knob rings, function keys and the ambient strip.
extension AudioService {
    /// Quit: every LED off (strip, function keys, rings).
    func allLEDsOff() {
        guard let c = controller else { return }
        var cmds: [AXProtocol.Command] = [AXProtocol.auraStrip(sdkMode: 0, r: 0, g: 0, b: 0, speed: 0)]
        for i in 0..<4 { cmds.append(AXProtocol.functionKeyLED(index: i, on: false, r: 0, g: 0, b: 0)) }
        cmds.append(AXProtocol.knobRings(sdkMode: 0, r: 0, g: 0, b: 0, speed: 0))
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

            if groups.contains(.knobs) && self.ringsKeepColors {
                await self.restoreRingLevelMode()
            } else if groups.contains(.knobs) {
                let k = AXProtocol.ledEffect(mode: s.ledKnob.mode.rawValue, peak: s.ledKnob.peak)
                // Rewriting config1 resets the rings for a moment: only when the effect really changes.
                var ringConfig: UInt8?
                if let reply = await c.transact(AXProtocol.readConfig1()), reply.count > 4 {
                    var cfg = reply[4] & ~0x0E
                    if k.sdk == 0 { cfg = reply[4] & ~0x06 } else if k.sdk == 7 { cfg |= 0x0A } else { cfg |= 0x0C }
                    if cfg != reply[4] { c.send(AXProtocol.config1(cfg)); self.lastRings = nil }
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
                if !burst.isEmpty { c.sendInOrder(burst) }
            }
            if groups.contains(.aura) { self.sendAura(self.auraOverride ?? s.ledAura) }
            if groups.contains(.buttons) { await self.sendFunctionKeyLEDs() }
        }
    }

    /// Function key LEDs: off, the key's own background color, or one custom color.
    func sendFunctionKeyLEDs() async {
        guard let c = controller, !ringsKeepColors else { return }
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
}
