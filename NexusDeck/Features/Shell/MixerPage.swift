import SwiftUI

extension MixerChannel {
    /// Colour of the channel's icon tile (two tones for the gradient).
    var tint: (String, String) {
        switch self {
        case .mic: ("#FF9F45", "#FF7A00")
        case .lineIn: ("#64D2FF", "#0A84FF")
        case .console: ("#BF5AF2", "#8E44EF")
        case .system: ("#FF6482", "#FF2D55")
        case .game: ("#30D158", "#248A3D")
        case .chat: ("#7D7AFF", "#5E5CE6")
        }
    }
}

/// Rounded square icon of a channel, filled with its colour.
struct ChannelTile: View {
    let channel: MixerChannel
    var size: CGFloat = 40
    @EnvironmentObject var store: ProfileStore
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27)
            .fill(LinearGradient(colors: [Color(hex: channel.tint.0), Color(hex: channel.tint.1)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: store.mixer.symbol(channel)).font(.system(size: size * 0.45, weight: .medium)).foregroundStyle(.white))
            .shadow(color: Color(hex: channel.tint.1).opacity(0.3), radius: 4, y: 2)
    }
}

/// Mixer: one vertical strip per channel, status chips and output volumes.
struct MixerPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                chip("Dual Mix", "circle.lefthalf.filled", store.mixer.dualMix) { audio.setDualMix(!store.mixer.dualMix) }
                chip("Tracce OBS", "record.circle", store.mixer.obsTracks) { audio.setOBSTracks(!store.mixer.obsTracks) }
                chip(audio.ducked ? "Ducking attivo" : "Ducking", "arrow.down.right.and.arrow.up.left", store.mixer.ducking.enabled) { ui.section = .ducking }
                chip(store.mixer.micMonitor ? "Monitor attivo" : "Monitor spento", store.mixer.micMonitor ? "headphones" : "headphones.slash", store.mixer.micMonitor) {
                    audio.setMonitor(.mic, bus: .creator, !store.mixer.micMonitor)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                ForEach(Array(MixerChannel.allCases.enumerated()), id: \.offset) { i, ch in
                    ChannelStrip(channel: ch, index: i)
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 12) {
                OutputCard(title: "Cuffie", subtitle: "Creator Mix", symbol: "headphones", value: \.headphonesVolume)
                    .frame(maxWidth: .infinity)
                OutputCard(title: "Line Out", subtitle: lineOutSource, symbol: "hifispeaker.fill", value: \.lineOutVolume)
                    .frame(maxWidth: .infinity)
                chatMicCard.frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
    }

    private var lineOutSource: String {
        ["Creator Mix", "Audience Mix", "Chat Mic"][min(2, max(0, store.library.device.lineOutSource))]
    }

    private var chatMicCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 16)).foregroundStyle(Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Chat Mic").font(.system(size: 12.5, weight: .semibold))
                Text("Voce per le app").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            .fixedSize()
            Spacer(minLength: 4)
            DarkPicker(selection: Binding(get: { store.library.device.chatMicWithEffects }, set: { store.library.device.chatMicWithEffects = $0; audio.applyDSP() }),
                       options: [(true, "Con effetti"), (false, "Senza effetti")]).frame(width: 118, height: 26)
        }
        .cardStyle()
    }

    private func chip(_ t: LocalizedStringKey, _ symbol: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(t).font(.system(size: 12, weight: on ? .semibold : .regular))
            }
            .foregroundStyle(on ? Theme.accent : Theme.textDim)
            .padding(.horizontal, 11).frame(height: 26)
            .background(on ? Theme.accent.opacity(0.15) : Theme.field)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// White (dark: graphite) rounded card with a hairline border.
    func cardStyle(padding: CGFloat = 14, radius: CGFloat = 12) -> some View {
        self.padding(.horizontal, padding).padding(.vertical, padding - 2)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
    }
}

/// One channel: icon, name, meter + vertical fader, value, mute (and monitor for the mic).
struct ChannelStrip: View {
    let channel: MixerChannel
    let index: Int
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var engine: ActionEngine
    @EnvironmentObject var ui: UIState

    private var bus: MixBus { store.mixer.dualMix ? store.mixer.activeMix : .creator }

    var body: some View {
        let s = store.mixer.mixes[bus]?.channels[channel] ?? ChannelState()
        let selected = ui.mixerKnob == index
        let custom = !(store.mixer.channelNames[channel.rawValue] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        VStack(spacing: 10) {
            ChannelTile(channel: channel)
            VStack(spacing: 2) {
                Text(store.mixer.name(channel).uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.3).lineLimit(1)
                Text(custom ? channel.title : " ").font(.system(size: 10.5)).foregroundStyle(Theme.textFaint).lineLimit(1)
            }
            HStack(spacing: 10) {
                LevelBar(value: Double(audio.meters[bus]?[channel] ?? 0) / 100)
                VFader(value: Binding(get: { Double(s.level) }, set: { audio.setLevel(channel, bus: bus, Int($0)); engine.syncStates() }),
                       muted: s.muted)
                LevelBar(value: Double(audio.meters[bus]?[channel] ?? 0) / 100)
            }
            .frame(maxHeight: .infinity)
            .padding(.vertical, 4)
            Text("\(s.level)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                + Text("%").font(.system(size: 11)).foregroundColor(Theme.textFaint)
            HStack(spacing: 6) {
                roundButton(channel == .mic ? (s.muted ? "mic.slash.fill" : "mic.fill") : (s.muted ? "speaker.slash.fill" : "speaker.wave.2.fill"),
                            style: s.muted ? .danger : .plain, help: "Muto") {
                    audio.toggleMute(channel, bus: bus); engine.syncStates()
                }
                if channel == .mic {
                    roundButton(store.mixer.micMonitor ? "headphones" : "headphones.slash", style: store.mixer.micMonitor ? .accent : .plain,
                                help: "Ascolto del microfono in cuffia") {
                        audio.setMonitor(.mic, bus: .creator, !store.mixer.micMonitor); engine.syncStates()
                    }
                }
            }
        }
        .padding(.top, 16).padding(.bottom, 14).padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Theme.accent : Theme.cardBorder, lineWidth: selected ? 2 : 1))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { ui.mixerKnob = index }
    }

    enum ButtonStyleKind { case plain, accent, danger }

    private func roundButton(_ symbol: String, style: ButtonStyleKind, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(style == .danger ? Color.white : style == .accent ? Theme.accent : Theme.textDim)
                .frame(width: 34, height: 26)
                .background(style == .danger ? Color.red : style == .accent ? Theme.accent.opacity(0.18) : Theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).help(help)
    }
}

/// Thin vertical level meter (green → yellow → red).
struct LevelBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(LinearGradient(stops: [.init(color: .green, location: 0), .init(color: .green, location: 0.65),
                                                 .init(color: .yellow, location: 0.85), .init(color: .red, location: 1)],
                                         startPoint: .bottom, endPoint: .top))
                    .frame(height: g.size.height)
                    .mask(alignment: .bottom) { Capsule().frame(height: g.size.height * max(0, min(1, value))) }
            }
        }
        .frame(width: 5)
        .animation(.linear(duration: 0.08), value: value)
    }
}

/// Vertical fader 0…100 with a white cap.
struct VFader: View {
    @Binding var value: Double
    var muted = false
    var tint: Color = Theme.accent
    var body: some View {
        GeometryReader { g in
            let f = CGFloat(value / 100)
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.track).frame(width: 6)
                Capsule().fill(muted ? Color.red.opacity(0.6) : tint).frame(width: 6, height: max(0, g.size.height * f))
                RoundedRectangle(cornerRadius: 8).fill(.white)
                    .frame(width: 28, height: 16)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                    .offset(y: -(g.size.height * f - 8))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let p = 1 - min(max(v.location.y / g.size.height, 0), 1)
                value = (Double(p) * 100).rounded()
            })
        }
        .frame(width: 30)
    }
}

/// Output volume (headphones / line out).
struct OutputCard: View {
    let title: LocalizedStringKey
    let subtitle: String
    let symbol: String
    let value: WritableKeyPath<DeviceSettings, Int>
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            .fixedSize()
            ThinSlider(value: Binding(get: { Double(store.library.device[keyPath: value]) }, set: { store.library.device[keyPath: value] = Int($0) })) { audio.applyDevice() }
                .frame(minWidth: 40, maxWidth: .infinity)
            Text("\(store.library.device[keyPath: value])%").font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.textDim).frame(width: 34, alignment: .trailing)
        }
        .cardStyle()
    }
}

// MARK: - Inspector

/// Settings of the selected channel (right pane of the Mixer).
struct ChannelInspector: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var ui: UIState

    var body: some View {
        if let i = ui.mixerKnob, i < MixerChannel.allCases.count {
            let ch = MixerChannel.allCases[i]
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        ChannelTile(channel: ch, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.mixer.name(ch)).font(.system(size: 14, weight: .semibold))
                            Text("Manopola \(i + 1) · \(store.mixer.dualMix ? store.mixer.activeMix.title : "Master Mix")")
                                .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                        }
                    }
                    InspectorSection("Uscite") {
                        routeRow("Cuffie", ch, .headphones)
                        routeRow("Diretta", ch, .stream)
                        if ch == .mic { routeRow("Chat", ch, .chat) }
                    }
                    if ch == .mic {
                        InspectorSection("Muto") {
                            InspectorRow("La manopola silenzia") {
                                DarkPicker(selection: Binding(get: { store.mixer.micMuteMode }, set: { store.mixer.micMuteMode = $0 }),
                                           options: [(.all, "Ovunque"), (.stream, "Solo diretta"), (.chat, "Solo chat")]).frame(width: 130)
                            }
                            InspectorRow("Ascolto in cuffia") {
                                PillToggle(isOn: Binding(get: { store.mixer.micMonitor }, set: { audio.setMonitor(.mic, bus: .creator, $0) }))
                            }
                            InspectorRow("Muto in chat") {
                                PillToggle(isOn: Binding(get: { store.mixer.chatMicMuted }, set: { store.mixer.chatMicMuted = $0; audio.applyMic() }))
                            }
                        }
                    }
                    InspectorSection("Aspetto") {
                        InspectorRow("Nome") {
                            TextField(ch.title, text: Binding(get: { store.mixer.channelNames[ch.rawValue] ?? "" },
                                                              set: { store.mixer.channelNames[ch.rawValue] = $0.isEmpty ? nil : String($0.prefix(16)) }))
                                .textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 140)
                        }
                        InspectorRow("Icona") {
                            IconPicker(selection: Binding(get: { store.mixer.symbol(ch) },
                                                          set: { store.mixer.channelIcons[ch.rawValue] = $0 == ch.columnSymbol ? nil : $0 }))
                        }
                    }
                    Text("Il nome compare anche come nome del dispositivo sul Mac. Le impostazioni valgono per il profilo «\(store.mixer.title)».")
                        .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "slider.vertical.3").font(.system(size: 28)).foregroundStyle(Theme.textFaint)
                Text("Seleziona un canale").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textDim)
                Text("per regolarne uscite, muto, nome e icona.").font(.system(size: 12)).foregroundStyle(Theme.textFaint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func routeRow(_ t: LocalizedStringKey, _ ch: MixerChannel, _ out: RouteOutput) -> some View {
        InspectorRow(t) {
            PillToggle(isOn: Binding(get: { store.mixer.isRouted(ch, to: out) }, set: { audio.setRoute(ch, out, $0) }))
        }
    }
}

/// Grouped rows with an uppercase caption, like the inspector panes of Apple apps.
struct InspectorSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textFaint).textCase(.uppercase).tracking(0.6)
            VStack(spacing: 0) {
                _VariadicView.Tree(DividedRows()) { content }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
    }
}

struct DividedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { c in
            c.padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            if c.id != last { Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.leading, 12) }
        }
    }
}

struct InspectorRow<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing
    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) { self.title = title; self.trailing = trailing() }
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12.5))
            Spacer(minLength: 6)
            trailing
        }
    }
}

// MARK: - OBS tracks page

struct OBSTracksPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                PillToggle(isOn: Binding(get: { store.mixer.obsTracks }, set: { audio.setOBSTracks($0) }))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tracce separate per OBS").font(.system(size: 14, weight: .semibold))
                    Text("Ogni canale diventa anche un ingresso [AM-IN]: in OBS ogni sorgente può andare sulla sua traccia (es. musica in diretta ma non nel VOD).")
                        .font(.system(size: 12)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                }
            }
            .cardStyle()
            InspectorSection("In OBS aggiungi «Acquisizione ingresso audio»") {
                deviceRow(.mic, "[AM-IN] Chat Mic", "Solo la voce")
                deviceRow(.lineIn, "[AM-IN] \(store.mixer.name(.lineIn).capitalized)", store.mixer.obsTracks ? "Line In fisico (via Audience Mix) + dispositivo Line In" : "Dispositivo Line In del Mac")
                deviceRow(.console, "[AM-IN] \(store.mixer.name(.console).capitalized)", "Dispositivo Console del Mac")
                deviceRow(.system, "[AM-IN] \(store.mixer.name(.system).capitalized)", "System e app instradate")
                deviceRow(.game, "[AM-IN] \(store.mixer.name(.game).capitalized)", "Game e app instradate")
                deviceRow(.chat, "[AM-IN] \(store.mixer.name(.chat).capitalized)", "Chat e app instradate")
            }
            .opacity(store.mixer.obsTracks ? 1 : 0.5)
            Text("Ogni ingresso segue la manopola, il muto e il ducking del suo canale. Per togliere la musica dal VOD di Twitch: in OBS → Proprietà audio avanzate, togli la musica dalla traccia del VOD.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func deviceRow(_ ch: MixerChannel, _ name: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            ChannelTile(channel: ch, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            Spacer()
        }
        .padding(.horizontal, 12).frame(minHeight: 46)
    }
}

