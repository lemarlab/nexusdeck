import SwiftUI

extension MixerChannel {
    var columnSymbol: String {
        switch self {
        case .mic: "mic.circle.fill"
        case .lineIn: "smallcircle.filled.circle"
        case .console: "gamecontroller.fill"
        case .system, .game, .chat: "display"
        }
    }
}
