import SwiftUI

// MARK: - Shared building blocks

/// Page header: big coloured icon, title, one line of explanation and an optional trailing control.
struct PageHero<Trailing: View>: View {
    let section: MainSection
    let subtitle: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 13).fill(section.tint)
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: section.symbol).font(.system(size: 23, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title).font(.system(size: 20, weight: .bold))
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.bottom, 8)
    }
}

extension PageHero where Trailing == EmptyView {
    init(section: MainSection, subtitle: LocalizedStringKey) { self.init(section: section, subtitle: subtitle) { EmptyView() } }
}

/// A titled group of rows (System Settings style), full width of the page.
struct FormGroup<Content: View>: View {
    let title: LocalizedStringKey
    var note: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                if let note { Text(note).font(.system(size: 11.5)).foregroundStyle(Theme.textDim) }
            }
            .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                _VariadicView.Tree(DividedRows()) { content }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
    }
}

/// Title with a secondary description, for the leading side of a row.
private struct RowLabel: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13))
            if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Compact segmented chooser with an orange selection.
private struct ChoiceBar<V: Hashable>: View {
    @Binding var selection: V
    let options: [(V, String)]
    var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.0) { o in
                let on = o.0 == selection
                Button { selection = o.0 } label: {
                    Text(o.1).font(.system(size: 11.5, weight: on ? .semibold : .regular)).lineLimit(1)
                        .foregroundStyle(on ? Color.white : Theme.textDim)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(on ? Theme.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - App routing

/// "Instradamento app": choose the mixer channel each app plays on.
struct AppRoutingPage: View {
    @EnvironmentObject var router: AppAudioRouter
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 22) {
                PageHero(section: .apps, subtitle: "Scegli su quale canale del mixer suona ogni app: il volume lo regola la manopola di quel canale.") {
                    Button { router.refresh() } label: { Label("Aggiorna", systemImage: "arrow.clockwise").font(.system(size: 12)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent).help("Aggiorna elenco")
                }
                if let e = router.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(e).font(.system(size: 12))
                        Button("Apri Privacy") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                        }
                    }
                }
                FormGroup(title: "In uso ora", note: router.apps.isEmpty ? nil : "\(router.apps.count) app") {
                    if router.apps.isEmpty {
                        Text("Nessuna app sta usando l'audio. Avvia la riproduzione in un'app e comparirà qui.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textDim).padding(.vertical, 10)
                    }
                    ForEach(router.apps, id: \.bundleID) { row($0, running: true) }
                }
                if !remembered.isEmpty {
                    FormGroup(title: "Ricordate", note: "usate quando l'app riparte") {
                        ForEach(remembered, id: \.bundleID) { row($0, running: false) }
                    }
                }
                Text("\"Predefinito\" lascia l'app sull'uscita audio scelta in macOS.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim).padding(.leading, 4)
            }
        }
        .onAppear { router.showingList = true }
        .onDisappear { router.showingList = false }
    }

    /// Routed apps that are not running (their route is kept).
    private var remembered: [AppAudioRouter.AudioApp] {
        let known = Set(router.apps.map(\.bundleID))
        return store.library.appRoutes.keys.sorted().filter { !known.contains($0) }.map { bid in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
            let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bid
            return .init(bundleID: bid, name: name, icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) }, playing: false)
        }
    }

    private func row(_ app: AppAudioRouter.AudioApp, running: Bool) -> some View {
        let options: [(String, String)] = [("", "Predefinito")] + AppAudioRouter.channels.map { ($0.0.rawValue, store.mixer.name($0.0)) }
        let route = Binding(get: { store.library.appRoutes[app.bundleID] ?? "" },
                            set: { router.setRoute(app.bundleID, $0.isEmpty ? nil : $0) })
        return HStack(spacing: 12) {
            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 30, height: 30) }
            else { Image(systemName: "app").font(.system(size: 22)).frame(width: 30, height: 30) }
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if running {
                    HStack(spacing: 5) {
                        Circle().fill(app.playing ? Color.green : Theme.textFaint).frame(width: 6, height: 6)
                        Text(app.playing ? "In riproduzione" : "In silenzio").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                }
            }
            Spacer(minLength: 12)
            if running {
                ChoiceBar(selection: route, options: options)
            } else {
                Picker("", selection: route) { ForEach(options, id: \.0) { Text($0.1).tag($0.0) } }
                    .labelsHidden().pickerStyle(.menu).frame(width: 150)
                Button("Dimentica") { router.setRoute(app.bundleID, nil) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
            }
        }
        .frame(minHeight: 40)
    }
}

// MARK: - Routing matrix

struct RoutingMatrix: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService

    private func outTitle(_ o: RouteOutput) -> String {
        switch o {
        case .headphones: "Cuffie"
        case .stream: store.mixer.dualMix ? "Diretta (Audience)" : "Diretta"
        case .chat: "Chat"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHero(section: .matrix, subtitle: "Scegli dove arriva ogni sorgente: in cuffia, in diretta o nella chat.")
            HStack(spacing: 10) {
                legend("headphones", "Cuffie", "quello che senti tu")
                legend("dot.radiowaves.left.and.right", "Diretta", "quello che sente il pubblico")
                legend("bubble.left.fill", "Chat", "solo il microfono")
            }
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Sorgente").frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(RouteOutput.allCases) { o in Text(outTitle(o)).frame(width: 150) }
                }
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.textDim)
                .padding(.horizontal, 14).frame(height: 38)
                ForEach(MixerChannel.allCases) { ch in
                    Rectangle().fill(Theme.cardBorder).frame(height: 1)
                    HStack(spacing: 0) {
                        HStack(spacing: 10) {
                            ChannelTile(channel: ch, size: 26)
                            Text(store.mixer.name(ch)).font(.system(size: 13))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(RouteOutput.allCases) { o in
                            Group {
                                if o == .chat && ch != .mic { Text("—").foregroundStyle(Theme.textFaint) } else { cell(ch, o) }
                            }
                            .frame(width: 150)
                        }
                    }
                    .padding(.horizontal, 14).frame(height: 44)
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
            if store.mixer.isRouted(.mic, to: .headphones) && !store.mixer.micMonitor {
                Text("Il microfono in cuffia si sente solo con il Monitor attivo.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim).padding(.top, -12).padding(.leading, 4)
            }
            FormGroup(title: "Microfono") {
                HStack {
                    RowLabel(title: "Pressione della manopola Mic", detail: "Cosa silenzia quando premi la manopola")
                    Spacer()
                    Picker("", selection: Binding(get: { store.mixer.micMuteMode }, set: { store.mixer.micMuteMode = $0 })) {
                        Text("Silenzia ovunque").tag(MicMuteMode.all)
                        Text("Silenzia solo la diretta").tag(MicMuteMode.stream)
                        Text("Silenzia solo la chat").tag(MicMuteMode.chat)
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 200)
                }
                HStack {
                    RowLabel(title: "Microfono muto in chat", detail: "Discord e le altre app non ti sentono, la diretta sì")
                    Spacer()
                    PillToggle(isOn: Binding(get: { store.mixer.chatMicMuted }, set: { store.mixer.chatMicMuted = $0; audio.applyMic() }))
                }
            }
        }
    }

    private func legend(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 12).frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    private func cell(_ ch: MixerChannel, _ o: RouteOutput) -> some View {
        let on = store.mixer.isRouted(ch, to: o)
        return Button { audio.setRoute(ch, o, !on) } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(on ? Theme.accent : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Theme.accent : Theme.textFaint.opacity(0.6), lineWidth: 1.5))
                .overlay(Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).opacity(on ? 1 : 0))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ducking

struct DuckingPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService

    private func set(_ f: (inout Ducking) -> Void) {
        f(&store.mixer.ducking)
        audio.applyMixer()
    }

    var body: some View {
        let d = store.mixer.ducking
        VStack(alignment: .leading, spacing: 22) {
            PageHero(section: .ducking, subtitle: "Abbassa automaticamente la musica e il gioco quando parli.") {
                PillToggle(isOn: Binding(get: { d.enabled }, set: { v in set { $0.enabled = v } }))
            }
            HStack(spacing: 16) {
                DuckGraph(ducking: d, active: audio.ducked)
                    .frame(height: 96).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(audio.ducked ? Theme.accent : Theme.textFaint).frame(width: 8, height: 8)
                            .shadow(color: audio.ducked ? Theme.accent : .clear, radius: 4)
                        Text(!d.enabled ? "Disattivato" : audio.ducked ? "Stai parlando" : "In attesa").font(.system(size: 12, weight: .semibold))
                    }
                    Text("Microfono ora \(Int(max(-90, audio.micInputDB))) dB").font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                    Text("Riduzione \(Int(d.reductionDB)) dB").font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                }
                .frame(width: 160, alignment: .leading)
            }
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
            Group {
                FormGroup(title: "Quando si attiva") {
                    sliderRow("Soglia voce", "\(Int(d.thresholdDB)) dB",
                              Binding(get: { d.thresholdDB }, set: { v in store.mixer.ducking.thresholdDB = v.rounded() }), -70...(-10))
                    sliderRow("Riduzione", "−\(Int(d.reductionDB)) dB",
                              Binding(get: { d.reductionDB }, set: { v in store.mixer.ducking.reductionDB = v.rounded() }), 3...40, commit: { audio.applyMixer() })
                    HStack {
                        RowLabel(title: "Solo in diretta", detail: "In cuffia i volumi restano invariati")
                        Spacer()
                        PillToggle(isOn: Binding(get: { d.streamOnly }, set: { v in set { $0.streamOnly = v } }))
                    }
                }
                FormGroup(title: "Tempi") {
                    sliderRow("Dissolvenza in uscita", "\(Int(d.fadeOutMs)) ms",
                              Binding(get: { d.fadeOutMs }, set: { v in store.mixer.ducking.fadeOutMs = (v / 50).rounded() * 50 }), 0...2000)
                    sliderRow("Rilascio", "\(Int(d.releaseMs)) ms",
                              Binding(get: { d.releaseMs }, set: { v in store.mixer.ducking.releaseMs = (v / 50).rounded() * 50 }), 100...3000)
                    sliderRow("Dissolvenza in entrata", "\(Int(d.fadeInMs)) ms",
                              Binding(get: { d.fadeInMs }, set: { v in store.mixer.ducking.fadeInMs = (v / 50).rounded() * 50 }), 0...4000)
                }
                FormGroup(title: "Sorgenti da abbassare") {
                    HStack(spacing: 8) {
                        ForEach(MixerChannel.allCases.filter { $0 != .mic }) { ch in chip(ch, on: d.channels.contains(ch.rawValue)) }
                    }
                    .padding(.vertical, 3)
                }
            }
            .opacity(d.enabled ? 1 : 0.5)
        }
    }

    private func chip(_ ch: MixerChannel, on: Bool) -> some View {
        Button {
            set { $0.channels = on ? $0.channels.filter { $0 != ch.rawValue } : $0.channels + [ch.rawValue] }
        } label: {
            HStack(spacing: 7) {
                ChannelTile(channel: ch, size: 20)
                Text(store.mixer.name(ch)).font(.system(size: 12, weight: on ? .semibold : .regular))
            }
            .foregroundStyle(on ? Theme.accent : Theme.text)
            .padding(.leading, 5).padding(.trailing, 12).frame(height: 30)
            .background(on ? Theme.accent.opacity(0.15) : Theme.field)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(on ? Theme.accent : Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(_ t: LocalizedStringKey, _ v: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, commit: (() -> Void)? = nil) -> some View {
        HStack(spacing: 14) {
            Text(t).font(.system(size: 13))
            Spacer()
            ThinSlider(value: value, range: range, onCommit: commit).frame(width: 280)
            Text(v).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim).monospacedDigit().frame(width: 70, alignment: .trailing)
        }
    }
}

/// Volume curve while talking: fade out, reduced level, release, fade in.
private struct DuckGraph: View {
    let ducking: Ducking
    let active: Bool

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let total = max(1, ducking.fadeOutMs + ducking.releaseMs + ducking.fadeInMs + 1600)
            let x0 = w * 400 / total
            let x1 = x0 + w * ducking.fadeOutMs / total
            let x2 = x1 + w * (800 + ducking.releaseMs) / total
            let x3 = x2 + w * ducking.fadeInMs / total
            let top = h * 0.18, low = top + (h * 0.7) * ducking.reductionDB / 40
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9).fill(Theme.field)
                Rectangle().fill(Theme.accent.opacity(active ? 0.16 : 0.08)).frame(width: max(0, x2 - x0)).offset(x: x0)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: top)); p.addLine(to: CGPoint(x: x0, y: top))
                    p.addLine(to: CGPoint(x: x1, y: low)); p.addLine(to: CGPoint(x: x2, y: low))
                    p.addLine(to: CGPoint(x: x3, y: top)); p.addLine(to: CGPoint(x: w, y: top))
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                Text("Parli").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                    .offset(x: x0 + 6, y: h - 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
}

// MARK: - OBS tracks

struct OBSTracksPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHero(section: .obs, subtitle: "Ogni canale diventa anche un ingresso audio del Mac, da mettere su una traccia diversa in OBS.") {
                PillToggle(isOn: Binding(get: { store.mixer.obsTracks }, set: { audio.setOBSTracks($0) }))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Ingressi disponibili in OBS").font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    track(.mic, "[AM-IN] Chat Mic", "Solo la voce")
                    track(.lineIn, "[AM-IN] \(store.mixer.name(.lineIn).capitalized)", store.mixer.obsTracks ? "Line In fisico + dispositivo Line In" : "Dispositivo Line In del Mac")
                    track(.console, "[AM-IN] \(store.mixer.name(.console).capitalized)", "Dispositivo Console del Mac")
                    track(.system, "[AM-IN] \(store.mixer.name(.system).capitalized)", "System e app instradate")
                    track(.game, "[AM-IN] \(store.mixer.name(.game).capitalized)", "Game e app instradate")
                    track(.chat, "[AM-IN] \(store.mixer.name(.chat).capitalized)", "Chat e app instradate")
                }
            }
            .opacity(store.mixer.obsTracks ? 1 : 0.5)
            FormGroup(title: "Come usarle · es. musica in diretta ma non nel VOD") {
                step(1, "In OBS aggiungi una sorgente «Acquisizione ingresso audio» per ogni canale e scegli il suo ingresso [AM-IN].")
                step(2, "Apri Proprietà audio avanzate e assegna ogni sorgente alla sua traccia.")
                step(3, "Togli la traccia della musica dalla traccia VOD di Twitch (Impostazioni → Uscita).")
            }
            Text("Ogni ingresso segue la manopola, il muto e il ducking del suo canale.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textDim).padding(.leading, 4)
        }
    }

    private func track(_ ch: MixerChannel, _ device: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            ChannelTile(channel: ch, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.mixer.name(ch)).font(.system(size: 13, weight: .semibold))
                Text(device).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textDim).lineLimit(1)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.textFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Theme.accent).clipShape(Circle())
            Text(text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
        }
    }
}
