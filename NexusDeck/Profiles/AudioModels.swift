import Foundation

enum MixerChannel: String, Codable, CaseIterable, Identifiable {
    case mic, lineIn = "line_in", console, system, game, chat
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mic: "MIC"
        case .lineIn: "LINE IN"
        case .console: "CONSOLE"
        case .system: "SYSTEM"
        case .game: "GAME"
        case .chat: "CHAT"
        }
    }
    var symbol: String {
        switch self {
        case .mic: "mic.fill"
        case .lineIn: "cable.coaxial"
        case .console: "gamecontroller.fill"
        case .system: "desktopcomputer"
        case .game: "flag.checkered"
        case .chat: "bubble.left.and.bubble.right.fill"
        }
    }
}

/// The two output mixes of the hardware mixer.
enum MixBus: Int, Codable, CaseIterable, Identifiable {
    case creator = 0, audience = 1
    var id: Int { rawValue }
    var title: String { self == .creator ? "Creator Mix" : "Audience Mix" }
}

struct ChannelState: Codable, Hashable {
    var level: Int = 50 // 0...100
    var muted = false
    var monitor = false
}

struct MixState: Codable, Hashable {
    var level: Int = 100
    var muted = false
    var channels: [MixerChannel: ChannelState] = Dictionary(uniqueKeysWithValues: MixerChannel.allCases.map { ($0, ChannelState(monitor: $0 == .mic)) })
}

enum MicInput: Int, Codable, CaseIterable, Identifiable {
    case xlr = 0, jack63 = 1
    var id: Int { rawValue }
    var title: String { self == .xlr ? "XLR" : "6.3 mm" }
}

struct MixerProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var mixes: [MixBus: MixState] = [.creator: MixState(), .audience: MixState()]
    var micInput: MicInput = .xlr
    var phantom48V = false
    var gainXLR = 25
    var gain48V = 20
    var gain63 = 0
    /// Which mix the knobs currently control.
    var activeMix: MixBus = .creator
    /// Whether knob changes are applied to both mixes.
    var linkMixes = true
    /// Single Mix: Audience Mix mirrors the Master (Creator) Mix. Dual Mix: two independent mixes.
    var dualMix = false
    /// Mic playback in the headphones (Creator Mix).
    var micMonitor = true
    var micName = "Microfono XLR"
    var micImage = ""
    /// Routing matrix: false = the source is kept out of that output ("\(output).\(channel)", see RouteOutput).
    var routes: [String: Bool] = [:]
    /// Mic muted in the Chat Mic output only.
    var chatMicMuted = false
    /// What a press of the Mic knob mutes.
    var micMuteMode: MicMuteMode = .all
    /// Custom channel names shown in the app and on the panel.
    var channelNames: [String: String] = [:]
    /// Custom channel icons (SF Symbol names).
    var channelIcons: [String: String] = [:]
    var ducking = Ducking()
    var screamGuard = ScreamGuard()
    /// OBS tracks mode: the Audience mix carries the physical Line In only (it becomes "Line In (OBS)"),
    /// every source reaches OBS on its own capture input.
    var obsTracks = false

    func isRouted(_ ch: MixerChannel, to out: RouteOutput) -> Bool { routes["\(out.rawValue).\(ch.rawValue)"] ?? true }
    func name(_ ch: MixerChannel) -> String {
        let n = channelNames[ch.rawValue]?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? ch.title : n.uppercased()
    }
    /// Icon of a channel in the app (custom SF Symbol or the default one).
    func symbol(_ ch: MixerChannel) -> String {
        let s = channelIcons[ch.rawValue] ?? ""
        return s.isEmpty ? ch.columnSymbol : s
    }
}

/// Outputs of the routing matrix. Headphones = Creator mix, Stream = Audience mix (Single Mix: the Mac's
/// "Creator Mix" device carries it too), Chat = the Chat Mic output (mic only).
enum RouteOutput: Int, CaseIterable, Identifiable {
    case headphones = 0, stream = 1, chat = 2
    var id: Int { rawValue }
}

enum MicMuteMode: Int, Codable, CaseIterable, Identifiable {
    case all = 0, stream = 1, chat = 2
    var id: Int { rawValue }
}

/// Scream protection: while the mic goes above a level (a shout), it is lowered or muted everywhere.
struct ScreamGuard: Codable, Hashable {
    enum Mode: Int, Codable, CaseIterable { case lower = 0, mute = 1 }
    var enabled = false
    var mode: Mode = .lower
    /// Mic input level (dBFS, after the gain) that counts as a shout.
    var thresholdDB: Double = -3
    /// How much the mic is lowered in "lower" mode.
    var reductionDB: Double = 20
    /// Time the protection stays on after the shout ends.
    var releaseMs: Double = 600
}

/// Lowers music and game while you speak (ducking).
struct Ducking: Codable, Hashable {
    var enabled = false
    /// Mic input level that counts as speech (dBFS, after the gain).
    var thresholdDB: Double = -38
    /// How much the ducked channels are lowered.
    var reductionDB: Double = 12
    /// Time the volume stays down after you stop speaking.
    var releaseMs: Double = 800
    /// Fade times: lowering (fade out) and coming back (fade in).
    var fadeOutMs: Double = 250
    var fadeInMs: Double = 800
    var channels: [String] = [MixerChannel.system.rawValue, MixerChannel.game.rawValue]
    /// Only in the stream (Audience) or also in the headphones.
    var streamOnly = false
}

// MARK: - Voice DSP

enum EQFilterType: Int, Codable, CaseIterable, Identifiable {
    case lowPass = 1, highPass = 2, lowShelf = 4, highShelf = 5, peaking = 6, notch = 7
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .lowShelf: "Low shelf"
        case .highPass: "High pass"
        case .lowPass: "Low pass"
        case .highShelf: "High shelf"
        case .notch: "Notch"
        case .peaking: "Peaking"
        }
    }
}

struct EQBand: Codable, Hashable {
    var frequency: Double
    var gain: Double
    var q: Double = 0.7
    var type: EQFilterType = .peaking
}

struct Compressor: Codable, Hashable {
    var threshold: Double = -18
    var ratio: Double = 0.75
    var attack: Double = 5
    var release: Double = 150
}

struct Reverb: Codable, Hashable {
    var roomSize: Double = 20
    var damp: Double = 1
    var density: Double = 1
    var diffusion: Double = 0.5
    var gain: Double = -8
    var wetGain: Double = 0
    var time: Double = 1
    /// "mode" of the reference profiles (weights the early diffusion).
    var mode: Double = 0
}

struct Echo: Codable, Hashable {
    var delay: Double = 150
    var dryGain: Double = -6
    var gain: Double = -12
    var time: Double = 5
}

struct NoiseGate: Codable, Hashable {
    var openThreshold: Double = -40
    var closeThreshold: Double = -46
    var attack: Double = 1
    /// "attackDebonce" in the reference app's profiles.
    var attackDebounce: Double = 0
    var hold: Double = 10
    var release: Double = 700
    var wetRatio: Double = 1
}

enum VoiceChanger: Int, Codable, CaseIterable, Identifiable {
    case off = 0, robot, monster, child, alien, radio
    var id: Int { rawValue }
}

struct DSPProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var eqEnabled = true
    var eqPresetIndex = 0
    var eqPresets: [[EQBand]] = DSPProfile.defaultEQPresets
    var compressorEnabled = true
    var compressorPresetIndex = 1
    var compressorPresets: [Compressor] = [Compressor(threshold: -96, ratio: 1, attack: 1, release: 1), Compressor()]
    var makeupGain: Double = 6
    var reverbEnabled = true
    var reverbPresetIndex = 1
    var reverbPresets: [Reverb] = [
        Reverb(roomSize: 12.15, damp: 1, density: 1, diffusion: 1, gain: -10),
        Reverb(roomSize: 20, damp: 1, density: 1, diffusion: 0.1, gain: -20),
        Reverb(roomSize: 20, damp: 0.85, density: 1, diffusion: 0.5, gain: -8),
        Reverb(roomSize: 23, damp: 0.6, density: 1, diffusion: 0.6, gain: -6, time: 2),
    ]
    var echoEnabled = false
    var echo = Echo()
    var noiseGateEnabled = true
    var noiseGate = NoiseGate()
    var voiceChanger: VoiceChanger = .off
    /// NexusDeck voice changer (software): selected voice (VoiceFX.voices) and whether it is on.
    var appVoice: Int = 1
    var appVoiceOn = false
    var appVoiceActive: Bool { appVoiceOn && appVoice > 0 }

    static let defaultFrequencies: [Double] = [50, 100, 250, 500, 1000, 4000, 8000, 16000]

    static var defaultEQPresets: [[EQBand]] {
        let flat = defaultFrequencies.enumerated().map { i, f in
            EQBand(frequency: f, gain: 0, type: i == 0 ? .highPass : (i == 7 ? .lowPass : .peaking))
        }
        // Factory presets of the reference app (eq0…eq4).
        let gains: [[Double]] = [
            [-9, 1, 0, -2, 0, -5, -3, -2],
            [5, 2, 1, 0, 0, 3, 5, 7],
            [0, 0, 0, 0, 0, 2, 5, 3],
            [0, 0, 1, 2, 2, 0, 0, 0],
            [6, 2, 1, 0, 0, 0, 0, 0],
        ]
        return gains.map { g in
            var p = flat
            for i in p.indices { p[i].gain = g[i] }
            return p
        }
    }

    var currentEQ: [EQBand] {
        get { eqPresets[eqPresetIndex] }
        set { eqPresets[eqPresetIndex] = newValue }
    }
}
