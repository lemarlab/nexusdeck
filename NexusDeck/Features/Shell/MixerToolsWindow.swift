import SwiftUI

/// Routing matrix, ducking and channel names (NexusDeck extras inspired by stream mixers).
struct MixerToolsWindow: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @State private var tab = 0

    var body: some View {
        ModalFrame(title: "Strumenti mixer", width: 760, height: 600) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 22) {
                    tabButton("Instradamento", 0)
                    tabButton("Ducking", 1)
                    tabButton("Nomi canali e icone", 2)
                    Spacer()
                }
                .padding(.horizontal, 26).frame(height: 36)
                Rectangle().fill(Theme.separator.opacity(0.5)).frame(height: 1)
                ScrollView {
                    Group {
                        switch tab {
                        case 0: RoutingMatrix()
                        case 1: DuckingPage()
                        default: ChannelNamesPage()
                        }
                    }
                    .padding(26)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func tabButton(_ t: LocalizedStringKey, _ i: Int) -> some View {
        Button { tab = i } label: {
            Text(t).font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(tab == i ? Theme.accent : Theme.textDim)
        }
        .buttonStyle(.plain)
    }
}

private struct RoutingMatrix: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService

    private func outTitle(_ o: RouteOutput) -> String {
        switch o {
        case .headphones: "Cuffie"
        case .stream: store.mixer.dualMix ? "Diretta (Audience)" : "Diretta"
        case .chat: "Chat (Chat Mic)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scegli dove arriva ogni sorgente. Il mix Chat Mic porta solo il microfono.")
                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
            Grid(alignment: .center, horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow {
                    Text("").frame(width: 140)
                    ForEach(RouteOutput.allCases) { o in
                        Text(outTitle(o)).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.textMid).frame(width: 120)
                    }
                }
                ForEach(MixerChannel.allCases) { ch in
                    GridRow {
                        HStack(spacing: 8) {
                            Image(systemName: store.mixer.symbol(ch)).foregroundStyle(Theme.accent)
                            Text(store.mixer.name(ch)).font(.system(size: 12, weight: .bold))
                        }
                        .frame(width: 140, alignment: .leading)
                        ForEach(RouteOutput.allCases) { o in
                            if o == .chat && ch != .mic {
                                Text("—").foregroundStyle(Theme.textDim).frame(width: 120)
                            } else {
                                cell(ch, o)
                            }
                        }
                    }
                }
            }
            if store.mixer.isRouted(.mic, to: .headphones) && !store.mixer.micMonitor {
                Text("Il microfono in cuffia si sente solo con il Monitor attivo.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            Divider().padding(.vertical, 6)
            Text("Pressione della manopola Mic").font(.system(size: 12.5, weight: .bold))
            DarkPicker(selection: Binding(get: { store.mixer.micMuteMode }, set: { store.mixer.micMuteMode = $0 }),
                       options: [(.all, "Silenzia ovunque"), (.stream, "Silenzia solo la diretta"), (.chat, "Silenzia solo la chat")])
                .frame(width: 260)
            HStack(spacing: 10) {
                PillToggle(isOn: Binding(get: { store.mixer.chatMicMuted }, set: { store.mixer.chatMicMuted = $0; audio.applyMic() }))
                Text("Microfono muto in chat (Chat Mic)").font(.system(size: 12)).foregroundStyle(Theme.textMid)
            }
        }
    }

    private func cell(_ ch: MixerChannel, _ o: RouteOutput) -> some View {
        let on = store.mixer.isRouted(ch, to: o)
        return Button { audio.setRoute(ch, o, !on) } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(on ? Theme.accent : Color.white.opacity(0.08))
                .overlay(Image(systemName: on ? "checkmark" : "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(on ? Color.black : Theme.textDim))
                .frame(width: 44, height: 26)
        }
        .buttonStyle(.plain).frame(width: 120)
    }
}

private struct DuckingPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService

    private func set(_ f: (inout Ducking) -> Void) {
        f(&store.mixer.ducking)
        audio.applyMixer()
    }

    var body: some View {
        let d = store.mixer.ducking
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                PillToggle(isOn: Binding(get: { d.enabled }, set: { v in set { $0.enabled = v } }))
                Text("Abbassa automaticamente le sorgenti quando parli").font(.system(size: 12.5, weight: .bold))
                Spacer()
                Circle().fill(audio.ducked ? Theme.accent : Color.white.opacity(0.15)).frame(width: 10, height: 10)
                Text(audio.ducked ? "Attivo" : "In attesa").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            row("Soglia voce", "\(Int(d.thresholdDB)) dB") {
                ThinSlider(value: Binding(get: { d.thresholdDB }, set: { v in store.mixer.ducking.thresholdDB = v.rounded() }), range: -70...(-10))
            }
            HStack {
                Text("Livello microfono ora: \(Int(max(-90, audio.micInputDB))) dB")
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                Spacer()
            }
            row("Riduzione", "−\(Int(d.reductionDB)) dB") {
                ThinSlider(value: Binding(get: { d.reductionDB }, set: { v in store.mixer.ducking.reductionDB = v.rounded() }), range: 3...40,
                           onCommit: { audio.applyMixer() })
            }
            row("Rilascio", "\(Int(d.releaseMs)) ms") {
                ThinSlider(value: Binding(get: { d.releaseMs }, set: { v in store.mixer.ducking.releaseMs = (v / 50).rounded() * 50 }), range: 100...3000)
            }
            row("Dissolvenza in uscita", "\(Int(d.fadeOutMs)) ms") {
                ThinSlider(value: Binding(get: { d.fadeOutMs }, set: { v in store.mixer.ducking.fadeOutMs = (v / 50).rounded() * 50 }), range: 0...2000)
            }
            row("Dissolvenza in entrata", "\(Int(d.fadeInMs)) ms") {
                ThinSlider(value: Binding(get: { d.fadeInMs }, set: { v in store.mixer.ducking.fadeInMs = (v / 50).rounded() * 50 }), range: 0...4000)
            }
            Text("Sorgenti da abbassare").font(.system(size: 12.5, weight: .bold))
            HStack(spacing: 18) {
                ForEach(MixerChannel.allCases.filter { $0 != .mic }) { ch in
                    let on = d.channels.contains(ch.rawValue)
                    Button {
                        set { $0.channels = on ? $0.channels.filter { $0 != ch.rawValue } : $0.channels + [ch.rawValue] }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? Theme.accent : Theme.textDim)
                            Text(store.mixer.name(ch)).font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                PillToggle(isOn: Binding(get: { d.streamOnly }, set: { v in set { $0.streamOnly = v } }))
                Text("Solo in diretta (in cuffia i volumi restano invariati)").font(.system(size: 12)).foregroundStyle(Theme.textMid)
            }
        }
    }

    private func row<C: View>(_ t: LocalizedStringKey, _ v: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 14) {
            Text(t).font(.system(size: 12)).foregroundStyle(Theme.textMid).frame(width: 150, alignment: .leading)
            c().frame(width: 320)
            Text(v).font(.system(size: 12, weight: .bold)).frame(width: 70, alignment: .trailing)
        }
    }
}

private struct ChannelNamesPage: View {
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dai un nome e un'icona a ogni canale (per esempio \"Music\" al posto di System). Il nome compare in maiuscolo nell'app e come nome del dispositivo sul Mac. Lascia vuoto per il nome standard.")
                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
            ForEach(MixerChannel.allCases) { ch in
                HStack(spacing: 14) {
                    IconPicker(selection: Binding(get: { store.mixer.symbol(ch) },
                                                  set: { store.mixer.channelIcons[ch.rawValue] = $0 == ch.columnSymbol ? nil : $0 }))
                    Text(ch.title).font(.system(size: 12, weight: .bold)).frame(width: 90, alignment: .leading)
                    TextField(ch.title, text: Binding(get: { store.mixer.channelNames[ch.rawValue] ?? "" },
                                                      set: { store.mixer.channelNames[ch.rawValue] = $0.isEmpty ? nil : String($0.prefix(16)) }))
                        .textFieldStyle(.roundedBorder).frame(width: 240)
                }
            }
        }
    }
}

/// Small icon button that opens a grid of SF Symbols suited to audio sources.
private struct IconPicker: View {
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
