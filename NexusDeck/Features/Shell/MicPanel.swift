import SwiftUI

/// Gain shown in dB (0...60) and mapped to the preamp register (0...119).
enum MicGain {
    static let maxDB = 60
    static func register(_ db: Int) -> Int { Int((Double(max(0, min(maxDB, db))) * 119 / Double(maxDB)).rounded()) }
}

enum MicType: Int, CaseIterable, Identifiable {
    case xlrDynamic, xlrCondenser, jack
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .xlrDynamic: "XLR dinamico"
        case .xlrCondenser: "XLR a condensatore (+48 V)"
        case .jack: "6,3 mm"
        }
    }
}

extension MixerProfile {
    var micType: MicType {
        get { micInput == .jack63 ? .jack : (phantom48V ? .xlrCondenser : .xlrDynamic) }
        set {
            micInput = newValue == .jack ? .jack63 : .xlr
            phantom48V = newValue == .xlrCondenser
        }
    }
    var currentGainDB: Int {
        get { micType == .jack ? gain63 : (micType == .xlrCondenser ? gain48V : gainXLR) }
        set {
            switch micType {
            case .jack: gain63 = newValue
            case .xlrCondenser: gain48V = newValue
            case .xlrDynamic: gainXLR = newValue
            }
        }
    }
}

extension DSPProfile {
    static let bassBands = 0...2, midBands = 3...5, trebleBands = 6...7

    /// Simplified 0...100 % control over a group of EQ bands (50 % = flat).
    func groupPercent(_ r: ClosedRange<Int>) -> Int {
        let eq = currentEQ
        let avg = r.map { eq[$0].gain }.reduce(0, +) / Double(r.count)
        return Int((avg / 15 * 50 + 50).rounded())
    }

    mutating func setGroupPercent(_ r: ClosedRange<Int>, _ pct: Int) {
        let target = Double(pct - 50) / 50 * 15
        let delta = target - Double(groupPercent(r) - 50) / 50 * 15
        var eq = currentEQ
        for i in r { eq[i].gain = max(-15, min(15, (eq[i].gain + delta).rounded())) }
        currentEQ = eq
    }
}

// MARK: - Microphone effect window

struct EQPreset: Identifiable {
    let id: String
    let title: String
    let gains: [Double]

    static let all: [EQPreset] = [
        .init(id: "flat", title: "Piatto", gains: [0, 0, 0, 0, 0, 0, 0, 0]),
        .init(id: "voice", title: "Voce chiara", gains: [-9, 1, 0, -2, 0, -5, -3, 2]),
        .init(id: "bright", title: "Più brillante", gains: [0, 0, 0, 0, 1, 3, 5, 6]),
        .init(id: "bass", title: "Più bassi", gains: [5, 4, 2, 0, 0, 0, 0, 0]),
        .init(id: "brightBass", title: "Brillante e corposo", gains: [5, 2, 1, 0, 0, 3, 5, 7]),
        .init(id: "radio", title: "Radio", gains: [-12, -6, 2, 4, 5, 3, -4, -10]),
        .init(id: "sm7bBroadcast", title: "SM7B Broadcast", gains: [-12, -2, -3, -1, 0, 4, 2, 1]),
        .init(id: "sm7bWarm", title: "SM7B Podcast caldo", gains: [-9, 1, -2, -1, 0, 2, 1, 0]),
        .init(id: "sm7bGaming", title: "SM7B Gaming", gains: [-12, -4, -3, 0, 1, 5, 3, 1]),
    ]
}

