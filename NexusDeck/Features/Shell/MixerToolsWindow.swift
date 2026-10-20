import SwiftUI

/// Small icon button that opens a grid of SF Symbols suited to audio sources.
struct IconPicker: View {
    @Binding var selection: String
    @State private var open = false

    static let symbols = [
        "music.note", "music.note.list", "headphones", "hifispeaker.fill", "speaker.wave.2.fill", "radio.fill",
        "gamecontroller.fill", "playstation.logo", "xbox.logo", "display", "desktopcomputer", "laptopcomputer",
        "tv.fill", "play.rectangle.fill", "film.fill", "mic.fill", "mic.circle.fill", "waveform",
        "bubble.left.and.bubble.right.fill", "message.fill", "phone.fill", "video.fill", "person.2.fill", "person.wave.2.fill",
        "bell.fill", "globe", "safari.fill", "guitars.fill", "pianokeys", "smallcircle.filled.circle",
        "cable.connector", "dot.radiowaves.left.and.right", "antenna.radiowaves.left.and.right", "star.fill", "heart.fill", "bolt.fill",
    ]

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: selection).font(.system(size: 14)).foregroundStyle(Theme.accent)
                .frame(width: 30, height: 26).background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).help("Cambia icona")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 6), spacing: 6) {
                ForEach(Self.symbols, id: \.self) { s in
                    Button { selection = s; open = false } label: {
                        Image(systemName: s).font(.system(size: 15))
                            .frame(width: 34, height: 30)
                            .background(s == selection ? Theme.accent.opacity(0.35) : Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }
}
