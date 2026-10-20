import Foundation

/// NexusDeck's own voice changer: real-time effects applied to the mic inside the audio bridge
/// (no allocation, no lock: everything lives in one pre-allocated block read by the IO thread).
///
/// Voices are combinations of classic effects (pitch shift, ring modulation, band-pass, distortion, echo).
enum VoiceFX {
    /// The voices offered in the app (id = position in this list, 0 = off).
    static let voices: [(name: String, symbol: String)] = [
        ("Spenta", "mic"),
        ("Robot", "cpu"),
        ("Scoiattolo", "hare.fill"),
        ("Gigante", "figure.stand"),
        ("Radio", "radio.fill"),
        ("Demone", "flame.fill"),
        ("Alieno", "sparkles"),
        ("Telefono", "phone.fill"),
        ("Caverna", "mountain.2.fill"),
    ]

    /// Mutable DSP state (one per bridge).
    struct State {
        var voice: Int32 = 0
        /// Gain of the filtered voice sent back to the mixer (0 = only on Chat Mic).
        var returnGain: Float = 1
        var sampleRate: Float = 48000
        /// Pitch shifter delay line.
        static let lineLength = 8192
        var line: UnsafeMutablePointer<Float>
        var write: Int = 0
        var phase: Float = 0          // pitch shifter read phase (0…1 of the window)
        var lfo: Float = 0            // modulation phase (0…1)
        var ring: Float = 0           // ring modulator phase (0…1)
        // Biquad band-pass / low-pass state
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
        var filterVoice: Int32 = -1
        // Echo
        static let echoLength = 48000
        var echo: UnsafeMutablePointer<Float>
        var echoPos: Int = 0
    }

    static func makeState() -> UnsafeMutablePointer<State> {
        let line = UnsafeMutablePointer<Float>.allocate(capacity: State.lineLength)
        line.initialize(repeating: 0, count: State.lineLength)
        let echo = UnsafeMutablePointer<Float>.allocate(capacity: State.echoLength)
        echo.initialize(repeating: 0, count: State.echoLength)
        let p = UnsafeMutablePointer<State>.allocate(capacity: 1)
        p.initialize(to: State(line: line, echo: echo))
        return p
    }

    static func freeState(_ p: UnsafeMutablePointer<State>) {
        p.pointee.line.deallocate()
        p.pointee.echo.deallocate()
        p.deallocate()
    }

    /// Per-voice parameters: pitch ratio, ring modulation (Hz, 0 = none), band-pass (centre Hz, Q; 0 = none),
    /// drive (0 = clean), echo (delay s, feedback, mix), pitch wobble (Hz, depth).
    private struct Params {
        var pitch: Float = 1
        var ring: Float = 0
        var bandHz: Float = 0, bandQ: Float = 0.7
        var lowpass: Float = 0
        var drive: Float = 0
        var echoTime: Float = 0, echoFeedback: Float = 0, echoMix: Float = 0
        var wobbleHz: Float = 0, wobble: Float = 0
        var gain: Float = 1
    }

    private static func params(_ v: Int32) -> Params {
        var p = Params()
        switch v {
        case 1: p.ring = 55; p.drive = 0.3; p.gain = 1.4                                   // Robot
        case 2: p.pitch = 1.65; p.gain = 1.1                                               // Scoiattolo
        case 3: p.pitch = 0.66; p.lowpass = 2500; p.echoTime = 0.09; p.echoFeedback = 0.25; p.echoMix = 0.25; p.gain = 1.4 // Gigante
        case 4: p.bandHz = 1600; p.bandQ = 0.9; p.drive = 0.6; p.gain = 1.6                // Radio
        case 5: p.pitch = 0.6; p.drive = 0.7; p.echoTime = 0.12; p.echoFeedback = 0.35; p.echoMix = 0.3; p.gain = 1.3 // Demone
        case 6: p.pitch = 1.3; p.wobbleHz = 6; p.wobble = 0.06; p.ring = 400; p.gain = 1.3  // Alieno
        case 7: p.bandHz = 1500; p.bandQ = 1.4; p.drive = 0.2; p.gain = 1.9                // Telefono
        case 8: p.echoTime = 0.28; p.echoFeedback = 0.55; p.echoMix = 0.5; p.lowpass = 4000 // Caverna
        default: break
        }
        return p
    }

    /// Processes `count` mono samples in place (IO thread).
    static func process(_ s: UnsafeMutablePointer<State>, _ buf: UnsafeMutablePointer<Float>, _ count: Int) {
        let v = s.pointee.voice
        guard v > 0 else { return }
        let p = params(v)
        let sr = s.pointee.sampleRate
        // Filter coefficients (recomputed when the voice changes).
        if s.pointee.filterVoice != v {
            s.pointee.filterVoice = v
            s.pointee.x1 = 0; s.pointee.x2 = 0; s.pointee.y1 = 0; s.pointee.y2 = 0
            if p.bandHz > 0 || p.lowpass > 0 {
                let f = p.bandHz > 0 ? p.bandHz : p.lowpass
                let q = p.bandHz > 0 ? p.bandQ : 0.707
                let w = 2 * Float.pi * f / sr, alpha = sin(w) / (2 * q), c = cos(w), a0 = 1 + alpha
                if p.bandHz > 0 {
                    s.pointee.b0 = alpha / a0; s.pointee.b1 = 0; s.pointee.b2 = -alpha / a0
                } else {
                    s.pointee.b0 = (1 - c) / 2 / a0; s.pointee.b1 = (1 - c) / a0; s.pointee.b2 = (1 - c) / 2 / a0
                }
                s.pointee.a1 = -2 * c / a0; s.pointee.a2 = (1 - alpha) / a0
            }
        }
        let L = State.lineLength
        let window: Float = 0.04 * sr           // 40 ms grains
        let line = s.pointee.line, echo = s.pointee.echo
        var write = s.pointee.write, phase = s.pointee.phase, lfo = s.pointee.lfo, ring = s.pointee.ring
        let useFilter = p.bandHz > 0 || p.lowpass > 0
        let echoDelay = Int(p.echoTime * sr)
        var echoPos = s.pointee.echoPos
        for i in 0..<count {
            var x = buf[i]
            // Pitch shift: two read taps sliding through a delay line, cross-faded (triangular window).
            if p.pitch != 1 || p.wobble > 0 {
                line[write] = x
                let ratio = p.pitch * (1 + p.wobble * sin(2 * .pi * lfo))
                phase += (1 - ratio) / window
                if phase >= 1 { phase -= 1 } else if phase < 0 { phase += 1 }
                func tap(_ ph: Float) -> Float {
                    let d = ph * window
                    var r = Float(write) - d
                    if r < 0 { r += Float(L) }
                    let i0 = Int(r) % L, i1 = (i0 + 1) % L, fr = r - Float(Int(r))
                    return line[i0] + (line[i1] - line[i0]) * fr
                }
                let ph2 = phase + 0.5 >= 1 ? phase - 0.5 : phase + 0.5
                let w1 = 1 - abs(2 * phase - 1), w2 = 1 - abs(2 * ph2 - 1)
                x = tap(phase) * w1 + tap(ph2) * w2
                write = (write + 1) % L
            }
            if p.wobbleHz > 0 { lfo += p.wobbleHz / sr; if lfo >= 1 { lfo -= 1 } }
            // Ring modulation (robot / alien).
            if p.ring > 0 {
                ring += p.ring / sr
                if ring >= 1 { ring -= 1 }
                x *= sin(2 * .pi * ring)
            }
            // Band-pass / low-pass.
            if useFilter {
                let y = s.pointee.b0 * x + s.pointee.b1 * s.pointee.x1 + s.pointee.b2 * s.pointee.x2 - s.pointee.a1 * s.pointee.y1 - s.pointee.a2 * s.pointee.y2
                s.pointee.x2 = s.pointee.x1; s.pointee.x1 = x; s.pointee.y2 = s.pointee.y1; s.pointee.y1 = y
                x = y
            }
            // Soft distortion.
            if p.drive > 0 { let k = 1 + p.drive * 8; x = tanh(x * k) / tanh(k) }
            // Echo.
            if echoDelay > 0 {
                var r = echoPos - echoDelay
                if r < 0 { r += State.echoLength }
                let e = echo[r]
                echo[echoPos] = x + e * p.echoFeedback
                echoPos = (echoPos + 1) % State.echoLength
                x = x + e * p.echoMix
            }
            buf[i] = max(-1, min(1, x * p.gain))
        }
        s.pointee.write = write; s.pointee.phase = phase; s.pointee.lfo = lfo; s.pointee.ring = ring; s.pointee.echoPos = echoPos
    }
}
