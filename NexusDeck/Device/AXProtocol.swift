import Foundation

/// Pure encoding/decoding of the controller's HID protocol (see PROTOCOL.md).
enum AXProtocol {
    static let featureSize = 64
    static let outputSize = 1024
    static let chunkPayload = 1012
    static let maxFrameBytes = 200_000
    static let panelWidth = 800
    static let panelHeight = 480
    static let mixerVolumeMax = 20

    struct Command {
        var bytes: [UInt8]
        var preDelayMs = 0
        var async = false

        var interDelayMs: Int {
            if bytes[0] == 0xFE { return [0x87, 0x88, 0xA3].contains(bytes[3]) ? 50 : 200 }
            if bytes[0] & 0x81 == 0x81 && bytes[1] == 0x10 { return 75 }
            return 0
        }
    }

    private static func packet(_ head: [UInt8]) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: featureSize)
        for (i, v) in head.enumerated() where i < featureSize { b[i] = v }
        return b
    }

    // MARK: Register file helpers

    static func write(_ reg: UInt8, _ data: [UInt8], pre: Int = 0, async: Bool = true) -> Command {
        Command(bytes: packet([0x01, 0x10, reg, UInt8(data.count)] + data), preDelayMs: pre, async: async)
    }

    static func read(_ reg: UInt8, _ count: UInt8) -> Command {
        Command(bytes: packet([0x81, 0x10, reg, count]))
    }

    static func dsp(_ cmd: UInt8, _ payload: [UInt8]) -> Command {
        let len = UInt8(payload.count + 5)
        var b: [UInt8] = [0xFE, 0x00, len, cmd] + payload
        let sum = b[2...].reduce(0) { ($0 + Int($1)) & 0xFF }
        b.append(UInt8(sum))
        return Command(bytes: packet(b), async: true)
    }

    // MARK: System

    static func backlight(_ v: Int) -> Command { Command(bytes: packet([0x01, 0x0A, UInt8(max(0, min(100, v)))])) }
    static func panelOn() -> Command { Command(bytes: packet([0x01, 0x0A, 0xAA])) }
    static func panelOff() -> Command { Command(bytes: packet([0x01, 0x0A, 0xFF])) }
    static func getBacklight() -> Command { Command(bytes: packet([0x81, 0x0A])) }
    static func firmwareVersion() -> Command { Command(bytes: packet([0x81, 0x01])) }
    static func levelMeters(_ on: Bool) -> Command { Command(bytes: packet([0x01, 0x03, on ? 1 : 0])) }
    static func bootAnimation() -> Command { Command(bytes: packet([0x01, 0x04, 0x01])) }
    static func powerSaving(enabled: Bool, minutes: Int) -> Command {
        var b = packet([0x01, 0xA0, 0x00, 0x04])
        b[0x15] = enabled ? 1 : 0
        b[0x16] = UInt8(max(0, min(255, minutes)))
        return Command(bytes: b)
    }
    static func getSerial() -> Command { Command(bytes: packet([0x81, 0xA0, 0x00, 0x01])) }
    static func saveToFlash() -> Command { write(0x0F, [0x02]) }
    static func enableKnobs(_ on: Bool) -> Command { write(0x1D, [on ? 0 : 1]) }

    // MARK: Mixer (AX310)

    static func mixerVolume(mixer: Int, channel: Int, value: Int) -> Command {
        write(UInt8(0x27 + 7 * mixer + channel), [UInt8(max(0, min(mixerVolumeMax, value)))], pre: 100)
    }
    static func mixerVolumes(mixer: Int, values: [Int]) -> Command {
        write(UInt8(0x27 + 7 * mixer), values.map { UInt8(max(0, min(mixerVolumeMax, $0))) } + [0])
    }
    static func readMixerVolumes(mixer: Int) -> Command { read(UInt8(0x27 + 7 * mixer), 7) }
    static func mixerMutes(_ masks: [UInt8]) -> Command { write(0x11, masks) }
    static func readMixerMute(mixer: Int) -> Command { read(UInt8(0x11 + mixer), 1) }
    static func lineOutSource(_ mixer: Int) -> Command { write(0x14, [UInt8(mixer)]) }
    static func headphoneSource(_ mixer: Int) -> Command { write(0x15, [UInt8(mixer)]) }
    static func lineOutVolume(_ v: Int) -> Command { write(0x3D, [UInt8(max(0, min(mixerVolumeMax, v)))], pre: 75) }
    static func headphoneVolume(_ v: Int) -> Command { write(0x3C, [UInt8(max(0, min(mixerVolumeMax, v)))], pre: 75) }
    /// Selects which mixer the hardware knobs drive (bit7 = link both mixes).
    static func knobControl(mixer: Int, linked: Bool) -> Command { write(0x21, [UInt8(mixer) | (linked ? 0x80 : 0)], pre: 100) }

    // MARK: Microphone

    /// bit0 phantom power, bits1-3 mic mode per mixer, bit4 mic table.
    static func micConfig(_ v: UInt8) -> Command { write(0x20, [v]) }
    static func readMicConfig() -> Command { read(0x20, 1) }
    /// Register 0x22: low nibble = mixer heard in the monitor, high nibble = sync (1 = mic monitor on, 3 = off, 0 = dual mix).
    static func micMonitor(mixer: UInt8, sync: UInt8) -> Command { write(0x22, [mixer | (sync << 4)]) }
    static func preampGain(_ g: Int) -> Command { write(0x1F, [UInt8(max(0, min(119, g)))]) }
    static func pgaAttenuation(_ v: Int) -> Command { write(0x23, [UInt8(max(0, min(8, v)))]) }

    // MARK: LEDs (see LED_PROTOCOL.md)

    /// Settings mode (0...8) -> device effect mode, whether the color is forced to white, whether speed applies.
    static func ledEffect(mode: Int, peak: Bool) -> (sdk: Int, white: Bool, speed: Bool) {
        switch mode {
        case 0: (0, false, false)
        case 1, 2: (3, false, false)
        case 3: (2, false, true)
        case 4: (4, true, true)
        case 5: (1, false, true)
        case 6: (5, true, true)
        case 7: (6, true, true)
        case 8: (peak ? 7 : 3, false, false)
        default: (3, false, false)
        }
    }

    /// The firmware drops LED writes that follow each other too closely (the reference app waits 250 ms).
    static let ledPreDelay = 250

    static func readConfig1() -> Command { read(0x1E, 1) }
    static func config1(_ v: UInt8) -> Command { write(0x1E, [v]) }

    /// All six knob rings.
    static func knobRings(sdkMode: Int, r: UInt8, g: UInt8, b: UInt8, speed: UInt8) -> Command {
        let effect: UInt8 = sdkMode == 0 ? 0 : (sdkMode >= 7 ? 0x1F : UInt8((sdkMode << 3) | 7))
        return write(0xC0, [0x01, 0xC0, 0x0A, r, g, b, speed, 0x00, effect, 0x80], pre: ledPreDelay)
    }

    /// One knob ring (0 = Mic … 5 = Chat), verified on hardware.
    static func knobRing(_ index: Int, sdkMode: Int, r: UInt8, g: UInt8, b: UInt8, speed: UInt8) -> Command {
        let effect: UInt8 = sdkMode == 0 ? 0 : (sdkMode >= 7 ? 0x1F : UInt8((sdkMode << 3) | 7))
        return write(0xC0, [0x01, UInt8(index), 0x0A, r, g, b, speed, 0x00, effect, 0x80], pre: ledPreDelay)
    }

    /// LED ids of function keys 0...3.
    static let functionKeyLEDs: [UInt8] = [0x3C, 0x3D, 0x3F, 0x3E]

    static func functionKeyLED(index: Int, on: Bool, r: UInt8, g: UInt8, b: UInt8) -> Command {
        write(0xC0, [0x00, functionKeyLEDs[index], 0x01, r, g, b, 0x00, 0x00, on ? 0x1F : 0x00, 0x80], pre: ledPreDelay)
    }

    /// Ambient light strip.
    static func auraStrip(sdkMode: Int, r: UInt8, g: UInt8, b: UInt8, speed: UInt8) -> Command {
        let codes: [UInt8] = [0x34, 0x2C, 0x38, 0x34, 0x28, 0x30, 0x24]
        let code = sdkMode < codes.count ? codes[sdkMode] : 0x20
        return write(0xE0, [0x01, code, 0x01, 0x20, speed, 0x00, 0x00, r, g, b], pre: ledPreDelay)
    }

    // MARK: DSP

    static func reverbMaster(_ on: Bool) -> Command { dsp(0x85, [on ? 1 : 0]) }
    static func noiseGateEnable(_ on: Bool) -> Command { dsp(0x9A, [on ? 1 : 0]) }
    static func compressorEnable(_ on: Bool) -> Command { dsp(0x9B, [on ? 1 : 0]) }
    static func eqEnable(_ on: Bool) -> [Command] { [dsp(0x87, [on ? 1 : 0]), dsp(0x88, [on ? 1 : 0]), dsp(0x9C, [on ? 1 : 0])] }
    static func voiceChanger(_ v: Int) -> Command { dsp(0x95, [UInt8(v)]) }
    static func systemSound(_ id: Int) -> Command { dsp(0x98, [UInt8(id)]) }

    private static func le16(_ v: Int) -> [UInt8] { let x = UInt16(truncatingIfNeeded: v); return [UInt8(x & 0xFF), UInt8(x >> 8)] }
    private static func le32(_ v: Int64) -> [UInt8] { let x = UInt32(truncatingIfNeeded: v); return (0..<4).map { UInt8((x >> (8 * $0)) & 0xFF) } }
    private static func dbToLinear(_ db: Double) -> Double { pow(10, db / 20) }

    /// Same layout as AxCorePrivate::setNoiseGate (AxEffect::NoiseGate: open, close, attack, attack debounce,
    /// hold, release, wet ratio). Times are milliseconds × 44.1.
    static func noiseGate(_ g: NoiseGate) -> Command {
        let attack = Int(Double(Int(g.attack)) * 44.1), debounce = Int(Double(Int(g.attackDebounce)) * 44.1)
        let hold = Int(Double(Int(g.hold)) * 44.1)
        let t4 = Int64(Double(Int(g.release)) * 44.1)
        var p: [UInt8] = []
        p += le16(Int(dbToLinear(g.openThreshold) * 32767))
        p += le16(Int(dbToLinear(g.closeThreshold) * 32767))
        p += le16(attack)
        p += le16(debounce)
        p += le16(hold)
        p += le32(t4)
        p += le16(Int(g.wetRatio * 32767))
        p += le16(32767 / (attack + 1))
        p += le32(Int64(0x7FFF_FFFF) / (t4 + 1))
        return dsp(0x9E, p)
    }

    static func compressor(_ a: Compressor, _ b: Compressor, makeup: Double) -> Command {
        func stage(_ c: Compressor) -> [UInt8] {
            le16(Int(c.threshold * 256)) + le16(Int(c.ratio * 4096)) + le16(7430 / (Int(c.attack) + 1)) + le16(7430 / (Int(c.release) + 1))
        }
        return dsp(0x9F, stage(a) + stage(b) + [UInt8(max(0, min(255, dbToLinear(makeup) * 16)))])
    }

    /// Reverb + echo block, byte for byte as AxCorePrivate::setReverb (AxEffect::Echo / Reverb, verified layout).
    /// `enabled` = bit0 reverb, bit1 echo (the DSP mixes in only the enabled effects).
    static func reverb(_ r: Reverb, echo: Echo, enabled: UInt8) -> Command {
        func g(_ db: Double) -> UInt8 { UInt8(truncatingIfNeeded: Int(pow(10, db.rounded() / 20) * 255)) }
        func u(_ v: Double) -> UInt8 { UInt8(truncatingIfNeeded: Int(v * 255)) }
        func decay(_ a: Double, _ t: Double) -> UInt8 {
            let v = Int((pow(10, -3 * a / (1000 * max(t, 0.001))) - 0.7) / 0.28 * 255)
            return UInt8(max(0, min(255, v)))
        }
        let delay = Int(echo.delay.rounded())
        var p: [UInt8] = []
        p.append(g(echo.gain))                                   // 4
        p.append(decay(r.roomSize, r.time))                      // 5
        p.append(u(r.damp))                                      // 6
        p.append(g(r.gain))                                      // 7
        p.append(0x40)                                           // 8
        p.append(g(echo.dryGain))                                // 9
        p.append(UInt8(truncatingIfNeeded: Int(pow(10, r.wetGain.rounded() / 20) * 128)))  // 10
        p.append(decay(Double(delay), echo.time))                // 11
        p.append(u(r.diffusion))                                 // 12
        p.append(0)                                              // 13
        p.append(u(r.diffusion * r.mode))                        // 14
        p += [0x4E, 0x04, 0x40]                                  // 15-17
        p.append(enabled)                                        // 18
        p += le16(3000 - delay * 11025 / 1000)                   // 19-20
        p.append(u(r.density))                                   // 21
        p += le16(Int(r.roomSize * -22050 / 340 + 1500))         // 22-23
        p.append(0)                                              // 24
        return dsp(0x94, p)
    }

    // MARK: EQ

    /// Device filter type codes.
    static func filterCode(_ t: EQFilterType) -> Int { t.rawValue }

    static func biquad(_ band: EQBand, fs: Double = 44100) -> [Double] {
        let K = tan(Double.pi * band.frequency / fs)
        let Q = max(band.q, 0.1)
        let V = pow(10, abs(band.gain) / 20)
        let K2 = K * K
        switch band.type {
        case .lowPass:
            let n = 1 / (1 + K / Q + K2)
            return [K2 * n, 2 * K2 * n, K2 * n, 2 * (K2 - 1) * n, (1 - K / Q + K2) * n]
        case .highPass:
            let n = 1 / (1 + K / Q + K2)
            return [n, -2 * n, n, 2 * (K2 - 1) * n, (1 - K / Q + K2) * n]
        case .notch:
            let n = 1 / (1 + K / Q + K2)
            return [(1 + K2) * n, 2 * (K2 - 1) * n, (1 + K2) * n, 2 * (K2 - 1) * n, (1 - K / Q + K2) * n]
        case .peaking:
            if band.gain >= 0 {
                let n = 1 / (1 + K / Q + K2)
                return [(1 + V / Q * K + K2) * n, 2 * (K2 - 1) * n, (1 - V / Q * K + K2) * n, 2 * (K2 - 1) * n, (1 - K / Q + K2) * n]
            } else {
                let n = 1 / (1 + V / Q * K + K2)
                return [(1 + K / Q + K2) * n, 2 * (K2 - 1) * n, (1 - K / Q + K2) * n, 2 * (K2 - 1) * n, (1 - V / Q * K + K2) * n]
            }
        case .lowShelf:
            let s2 = sqrt(2.0), s2V = sqrt(2 * V)
            if band.gain >= 0 {
                let n = 1 / (1 + s2 * K + K2)
                return [(1 + s2V * K + V * K2) * n, 2 * (V * K2 - 1) * n, (1 - s2V * K + V * K2) * n, 2 * (K2 - 1) * n, (1 - s2 * K + K2) * n]
            } else {
                let n = 1 / (1 + s2V * K + V * K2)
                return [(1 + s2 * K + K2) * n, 2 * (K2 - 1) * n, (1 - s2 * K + K2) * n, 2 * (V * K2 - 1) * n, (1 - s2V * K + V * K2) * n]
            }
        case .highShelf:
            let s2 = sqrt(2.0), s2V = sqrt(2 * V)
            if band.gain >= 0 {
                let n = 1 / (1 + s2 * K + K2)
                return [(V + s2V * K + K2) * n, 2 * (K2 - V) * n, (V - s2V * K + K2) * n, 2 * (K2 - 1) * n, (1 - s2 * K + K2) * n]
            } else {
                let n = 1 / (V + s2V * K + K2)
                return [(1 + s2 * K + K2) * n, 2 * (K2 - 1) * n, (1 - s2 * K + K2) * n, 2 * (K2 - V) * n, (V - s2V * K + K2) * n]
            }
        }
    }

    static func eqBand(index: Int, _ band: EQBand) -> Command {
        let c = biquad(band)
        var shift = 0
        while c.contains(where: { abs($0) / pow(2, Double(shift)) >= 1 }) && shift < 8 { shift += 1 }
        let scale = pow(2, Double(shift))
        var p: [UInt8] = [UInt8(index), UInt8(filterCode(band.type)), UInt8(shift)]
        for v in c {
            let x = (v / scale * 2147483648).rounded(.toNearestOrAwayFromZero)
            p += le32(Int64(max(-2147483648, min(2147483647, x))))
        }
        return dsp(0xA3, p)
    }

    // MARK: Panel frames

    /// Splits a JPEG frame into 1024-byte output reports.
    static func frameChunks(_ jpeg: Data, format: UInt8 = 0, width: Int = 0, height: Int = 0) -> [[UInt8]] {
        let bytes = [UInt8](jpeg)
        var out: [[UInt8]] = []
        var offset = 0
        var seq = 0
        repeat {
            let n = min(chunkPayload, bytes.count - offset)
            let last = offset + n >= bytes.count
            var r = [UInt8](repeating: 0, count: outputSize)
            r[0] = UInt8(seq & 0xFF)
            r[1] = last ? 1 : 0
            r[2] = last ? 1 : 0
            r[3] = format
            r[4] = UInt8(width & 0xFF); r[5] = UInt8(width >> 8)
            r[6] = UInt8(height & 0xFF); r[7] = UInt8(height >> 8)
            r[8] = UInt8(n & 0xFF); r[9] = UInt8(n >> 8)
            for i in 0..<n { r[12 + i] = bytes[offset + i] }
            let sum = r[12...].reduce(0) { ($0 + Int($1)) & 0xFFFF }
            r[10] = UInt8(sum & 0xFF); r[11] = UInt8(sum >> 8)
            out.append(r)
            offset += n
            seq += 1
        } while offset < bytes.count
        return out
    }

    // MARK: Input

    enum Event: Equatable {
        case functionKeys(mask: UInt8)
        case touch(x: Int, y: Int)
        case touchUp
        case gesture(Gesture)
        case knobPress(mask: UInt8)
        case knobValue(index: Int, value: Int, muted: Bool)
        case levels([Int])
        case renderAck
    }

    enum Gesture: Equatable { case up, down, left, right }

    struct InputState {
        var keys: UInt8 = 0
        var touching = false
        var lastX = -1, lastY = -1
        var gesture: UInt8 = 0
        var knobPress: UInt8 = 0
        var knobValues = [Int](repeating: -1, count: 6)
    }

    static func decode(_ data: Data, state: inout InputState) -> [Event] {
        let r = [UInt8](data)
        guard r.count >= 58 else { return [] }
        let sum = r[0..<57].reduce(0) { ($0 + Int($1)) & 0xFF }
        guard UInt8(sum) == r[57] else { return [] }
        var ev: [Event] = []

        let rawKeys = r[0] & 0x0F
        let keys = ((rawKeys & 1) << 3) | ((rawKeys & 2) << 1) | ((rawKeys & 4) >> 1) | ((rawKeys & 8) >> 3)
        if keys != state.keys { state.keys = keys; ev.append(.functionKeys(mask: keys)) }

        let touching = r[0] & 0x10 != 0
        if touching {
            let x = Int(r[2]) | Int(r[3]) << 8, y = Int(r[4]) | Int(r[5]) << 8
            if x != state.lastX || y != state.lastY { state.lastX = x; state.lastY = y; ev.append(.touch(x: x, y: y)) }
            if r[1] != state.gesture {
                state.gesture = r[1]
                switch r[1] {
                case 0x10: ev.append(.gesture(.down))
                case 0x14: ev.append(.gesture(.left))
                case 0x18: ev.append(.gesture(.up))
                case 0x1C: ev.append(.gesture(.right))
                default: break
                }
            }
        } else if state.touching {
            state.lastX = -1; state.lastY = -1; state.gesture = 0
            ev.append(.touchUp)
        }
        state.touching = touching

        if r[6] != state.knobPress { state.knobPress = r[6]; ev.append(.knobPress(mask: r[6])) }
        // Reports with no knob/touch data (meter-only) carry zeros in bytes 8...13.
        let hasKnobData = r[8..<14].contains { $0 != 0 } || r[7] != 0
        if hasKnobData {
            for i in 0..<6 {
                let raw = Int(r[8 + i])
                if raw != state.knobValues[i] {
                    let first = state.knobValues[i] < 0
                    state.knobValues[i] = raw
                    if !first || r[7] & (1 << i) != 0 { ev.append(.knobValue(index: i, value: raw & 0x1F, muted: raw & 0x40 != 0)) }
                }
            }
        }
        if r[17] == 1 {
            // Raw samples (big-endian u16); scaled by channel volume/mute in AudioService, as the reference app does.
            var levels: [Int] = []
            for i in 0..<12 { levels.append(Int(r[18 + 2 * i]) << 8 | Int(r[19 + 2 * i])) }
            ev.append(.levels(levels))
        }
        if r[56] == 1 { ev.append(.renderAck) }
        return ev
    }
}
