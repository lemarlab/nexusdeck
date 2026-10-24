import SwiftUI

/// "Microfono" page: microphone card (type, gain, live level), the effect chain and the settings of the selected effect.
struct MicPage: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @State private var applyTask: Task<Void, Never>?
    @State private var calibrating: Int?
    @State private var confirm48V = false
    @State private var renaming = false
    @State private var name = ""

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 22) {
                micCard
                chain
                detail
                screamGuard
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Se l'audio con gli effetti suona male, prova a ridurre il guadagno o il livello degli effetti.")
                }
                .font(.system(size: 11.5)).foregroundStyle(Theme.textDim).padding(.leading, 4)
            }
        }
        .confirmationDialog("Attivare l'alimentazione phantom +48 V?", isPresented: $confirm48V) {
            Button("Attiva +48 V") { store.mixer.micType = .xlrCondenser; audio.applyMic() }
            Button("Annulla", role: .cancel) {}
        } message: { Text("Usa il +48 V solo con microfoni a condensatore che lo richiedono.") }
        .alert("Nome del microfono", isPresented: $renaming) {
            TextField("Nome", text: $name)
            Button("OK") { if !name.isEmpty { store.mixer.micName = name } }
            Button("Annulla", role: .cancel) {}
        }
    }

    // MARK: Microphone card

    private var micCard: some View {
        let phantom = store.mixer.micType == .xlrCondenser
        return HStack(spacing: 20) {
            micImage.frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(store.mixer.micName).font(.system(size: 20, weight: .bold)).lineLimit(1)
                    Button { name = store.mixer.micName; renaming = true } label: { Image(systemName: "pencil") }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent).help("Rinomina microfono")
                }
                HStack(spacing: 8) {
                    Picker("", selection: Binding(get: { store.mixer.micType }, set: { t in
                        if t == .xlrCondenser && !store.mixer.phantom48V { confirm48V = true } else { store.mixer.micType = t; audio.applyMic() }
                    })) {
                        ForEach(MicType.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 160)
                    Text(phantom ? "+48 V attivo" : "+48 V spento")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(phantom ? Color(hex: "#FF453A") : Theme.textDim)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(phantom ? Color(hex: "#FF3B30").opacity(0.15) : Theme.field)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Button("Cambia immagine…") { chooseImage() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
            }
            .frame(width: 280, alignment: .leading)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                Text("Livello in ingresso").font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                LevelMeter(db: audio.micInputDB, threshold: store.dsp.noiseGateEnabled ? store.dsp.noiseGate.openThreshold : nil)
                    .frame(height: 8)
                HStack {
                    ForEach(["−60", "−40", "−20", "−6", "0 dB"], id: \.self) { t in
                        Text(t).font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                        if t != "0 dB" { Spacer(minLength: 0) }
                    }
                }
                HStack(spacing: 12) {
                    Text("Guadagno").font(.system(size: 13)).frame(width: 70, alignment: .leading)
                    ThinSlider(value: Binding(get: { Double(store.mixer.currentGainDB) },
                                              set: { store.mixer.currentGainDB = Int($0.rounded()); audio.applyMic() }),
                               range: 0...Double(MicGain.maxDB))
                    Text("\(store.mixer.currentGainDB) dB").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.textDim).frame(width: 50, alignment: .trailing)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: 340)
        }
        .padding(18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    @ViewBuilder private var micImage: some View {
        if !store.mixer.micImage.isEmpty, let img = ImageCache.image(at: ProfileStore.iconFolder.appendingPathComponent(store.mixer.micImage)) {
            Image(nsImage: img).resizable().scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [Color(hex: "#FFB340"), Color(hex: "#FF7A00")], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: "mic.fill").font(.system(size: 38, weight: .medium)).foregroundStyle(.white))
                .shadow(color: Color(hex: "#FF7A00").opacity(0.3), radius: 8, y: 4)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let n = "mic-" + UUID().uuidString + "." + url.pathExtension
        if (try? FileManager.default.copyItem(at: url, to: ProfileStore.iconFolder.appendingPathComponent(n))) != nil { store.mixer.micImage = n }
    }

    // MARK: Effect chain

    private func info(_ t: MicEffectTab) -> (symbol: String, tint: String, detail: String) {
        switch t {
        case .noiseGate: ("waveform.badge.minus", "#30B0C7", "Taglia i rumori di fondo")
        case .compressor: ("arrow.down.right.and.arrow.up.left", "#5E5CE6", "Livella il volume")
        case .equalizer: ("slider.vertical.3", "#FF9500", EQPreset.all.first { $0.gains == store.dsp.currentEQ.map(\.gain) }?.title ?? "Personalizzato")
        case .echo: ("dot.radiowaves.right", "#34C759", "Ripete la voce")
        case .reverb: ("circle.dotted", "#BF5AF2", ["Stanza piccola", "Spazio piccolo", "Sala", "Spazio ampio"][min(3, max(0, store.dsp.reverbPresetIndex))])
        }
    }

    private var chain: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Catena effetti").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("La voce passa da sinistra a destra · clicca un effetto per regolarlo").font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 4)
            HStack(spacing: 0) {
                ForEach(Array(MicEffectTab.allCases.enumerated()), id: \.element) { i, t in
                    if i > 0 { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textFaint).frame(width: 22) }
                    chainTile(t)
                }
            }
        }
    }

    private func chainTile(_ t: MicEffectTab) -> some View {
        let sel = ui.micTab == t
        let on = enabled(t).wrappedValue
        let i = info(t)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SidebarIcon(symbol: i.symbol, tint: Color(hex: i.tint))
                Spacer()
                Toggle("", isOn: enabled(t)).toggleStyle(.switch).controlSize(.mini).labelsHidden().tint(Theme.accent)
            }
            Text(t.title).font(.system(size: 13, weight: .semibold))
            Text(on ? i.detail : "Spento").font(.system(size: 11)).foregroundStyle(Theme.textDim).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(sel ? Theme.accent : Theme.cardBorder, lineWidth: sel ? 2 : 1))
        .opacity(on || sel ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { ui.micTab = t } }
    }

    // MARK: Selected effect

    private var detail: some View {
        let t = ui.micTab
        let i = info(t)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SidebarIcon(symbol: i.symbol, tint: Color(hex: i.tint))
                Text(t.title).font(.system(size: 17, weight: .bold))
                Spacer()
                if t == .noiseGate {
                    if let left = calibrating {
                        ProgressView().controlSize(.small)
                        Text("Resta in silenzio… \(left)").font(.system(size: 12)).foregroundStyle(Theme.textMid)
                    } else {
                        Button("Calibra…") { calibrateGate() }
                            .help("Misura il fruscio del microfono in 3 secondi di silenzio e imposta la soglia appena sopra.")
                    }
                }
                Button { resetTab() } label: { Label("Ripristina", systemImage: "arrow.counterclockwise").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                _VariadicView.Tree(DividedRows()) { settings }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
            .opacity(enabled(t).wrappedValue ? 1 : 0.5)
            .allowsHitTesting(enabled(t).wrappedValue)
        }
    }

    @ViewBuilder private var settings: some View {
        switch ui.micTab {
        case .noiseGate:
            GateGraph(threshold: store.dsp.noiseGate.openThreshold).frame(height: 140).padding(.horizontal, -12).padding(.vertical, -9)
            row("Soglia", "\(Int(store.dsp.noiseGate.openThreshold)) dB", Binding(get: { store.dsp.noiseGate.openThreshold }, set: {
                // One threshold: the gate closes 6 dB below where it opens.
                store.dsp.noiseGate.openThreshold = $0.rounded()
                store.dsp.noiseGate.closeThreshold = $0.rounded() - 6
                apply()
            }), -80...0)
            row("Attacco", "\(Int(store.dsp.noiseGate.attack)) ms", dsp(\.noiseGate.attack), 0...100)
            row("Mantenimento", "\(Int(store.dsp.noiseGate.hold)) ms", dsp(\.noiseGate.hold), 0...500)
            row("Rilascio", "\(Int(store.dsp.noiseGate.release)) ms", dsp(\.noiseGate.release, step: 10), 0...2000)
        case .compressor:
            let i = store.dsp.compressorPresetIndex
            let c = store.dsp.compressorPresets[i]
            CompressorGraph(threshold: c.threshold, ratio: c.ratio).frame(height: 140).padding(.horizontal, -12).padding(.vertical, -9)
            row("Soglia", "\(Int(c.threshold)) dB", dsp(\.compressorPresets[i].threshold), -60...0)
            row("Rapporto", "\(Int((c.ratio * 100).rounded())) %", Binding(get: { store.dsp.compressorPresets[i].ratio * 100 },
                                                                           set: { store.dsp.compressorPresets[i].ratio = $0.rounded() / 100; apply() }), 0...100)
            row("Attacco", "\(Int(c.attack)) ms", dsp(\.compressorPresets[i].attack), 1...200)
            row("Rilascio", "\(Int(c.release)) ms", dsp(\.compressorPresets[i].release), 1...1000)
            row("Guadagno in uscita", "\(Int(store.dsp.makeupGain)) dB", dsp(\.makeupGain), 0...24)
        case .equalizer:
            EQGraph(gains: store.dsp.currentEQ.map(\.gain)).frame(height: 140).padding(.horizontal, -12).padding(.vertical, -9)
            HStack(spacing: 14) {
                Text("Preimpostazione").font(.system(size: 13))
                Spacer()
                pills(EQPreset.all.map { ($0.id, $0.title) } + [("custom", "Personalizzato")], selected: matchingPreset) { id in
                    guard let p = EQPreset.all.first(where: { $0.id == id }) else { return }
                    var eq = store.dsp.currentEQ
                    for i in eq.indices { eq[i].gain = p.gains[i] }
                    store.dsp.currentEQ = eq; apply()
                }
            }
            HStack(spacing: 0) {
                ForEach(store.dsp.currentEQ.indices, id: \.self) { i in
                    let b = store.dsp.currentEQ[i]
                    VStack(spacing: 8) {
                        Text(b.gain > 0 ? "+\(Int(b.gain))" : "\(Int(b.gain))").font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                        VerticalTrack(value: Binding(get: { b.gain }, set: { var eq = store.dsp.currentEQ; eq[i].gain = $0; store.dsp.currentEQ = eq; apply() }),
                                      range: -15...15)
                            .frame(width: 24, height: 130)
                        Text(b.frequency >= 1000 ? "\(Int(b.frequency / 1000)) kHz" : "\(Int(b.frequency)) Hz")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
        case .echo:
            row("Livello", "\(Int(store.dsp.echo.gain)) dB", dsp(\.echo.gain), -40...0)
            row("Tempo", "\(Int(store.dsp.echo.time)) s", dsp(\.echo.time), 1...10)
            row("Ritardo", "\(Int(store.dsp.echo.delay)) ms", dsp(\.echo.delay), 10...270)
        case .reverb:
            let i = store.dsp.reverbPresetIndex
            let r = store.dsp.reverbPresets[i]
            HStack(spacing: 14) {
                Text("Ambiente").font(.system(size: 13))
                Spacer()
                pills([(0, "Stanza piccola"), (1, "Spazio piccolo"), (2, "Sala"), (3, "Spazio ampio")], selected: i) {
                    store.dsp.reverbPresetIndex = $0; apply()
                }
            }
            row("Livello", "\(Int(r.gain)) dB", dsp(\.reverbPresets[i].gain), -40...0)
            row("Tempo", "\(Int(r.time)) s", dsp(\.reverbPresets[i].time), 1...10)
            row("Dimensione stanza", String(format: "%.2f m³", r.roomSize), dsp(\.reverbPresets[i].roomSize, step: 0.01), 1...40)
            row("Smorzamento", "\(Int((r.damp * 100).rounded())) %", Binding(get: { store.dsp.reverbPresets[i].damp * 100 },
                                                                         set: { store.dsp.reverbPresets[i].damp = $0.rounded() / 100; apply() }), 0...100)
            row("Diffusione", "\(Int((r.diffusion * 100).rounded())) %", Binding(get: { store.dsp.reverbPresets[i].diffusion * 100 },
                                                                            set: { store.dsp.reverbPresets[i].diffusion = $0.rounded() / 100; apply() }), 0...100)
        }
    }

    private func row(_ t: LocalizedStringKey, _ v: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 14) {
            Text(t).font(.system(size: 13))
            Spacer()
            ThinSlider(value: value, range: range).frame(width: 300)
            Text(v).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim).monospacedDigit().frame(width: 76, alignment: .trailing)
        }
    }

    private func pills<V: Hashable>(_ options: [(V, String)], selected: V, _ pick: @escaping (V) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { o in
                let on = o.0 == selected
                Button { pick(o.0) } label: {
                    Text(o.1).font(.system(size: 11.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white : Theme.textDim)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(on ? Theme.accent : Theme.field)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Scream protection

    private var screamGuard: some View {
        let g = store.mixer.screamGuard
        func set(_ f: (inout ScreamGuard) -> Void) { f(&store.mixer.screamGuard); audio.updateScreamGuard() }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SidebarIcon(symbol: "speaker.wave.3.fill", tint: Color(hex: "#FF3B30"))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Protezione urla").font(.system(size: 17, weight: .bold))
                    Text("Se urli nel microfono, la voce viene abbassata o silenziata finché il livello non torna normale.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                }
                Spacer()
                if g.enabled {
                    HStack(spacing: 6) {
                        Circle().fill(audio.screaming ? Color(hex: "#FF3B30") : Theme.textFaint).frame(width: 8, height: 8)
                            .shadow(color: audio.screaming ? Color(hex: "#FF3B30") : .clear, radius: 4)
                        Text(audio.screaming ? (g.mode == .mute ? "Microfono silenziato" : "Voce abbassata") : "In ascolto")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                PillToggle(isOn: Binding(get: { g.enabled }, set: { v in set { $0.enabled = v } }))
            }
            .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                _VariadicView.Tree(DividedRows()) {
                    HStack(spacing: 14) {
                        Text("Quando urli").font(.system(size: 13))
                        Spacer()
                        pills([(ScreamGuard.Mode.lower, "Abbassa la voce"), (.mute, "Silenzia il microfono")], selected: g.mode) { m in set { $0.mode = m } }
                    }
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Livello di urlo").font(.system(size: 13))
                            Text("Ora \(Int(max(-60, audio.micInputDB))) dB · più è vicino a 0, più forte devi urlare")
                                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        ThinSlider(value: Binding(get: { g.thresholdDB }, set: { v in store.mixer.screamGuard.thresholdDB = v.rounded() }), range: -30...0)
                            .frame(width: 300)
                        Text("\(Int(g.thresholdDB)) dB").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
                            .monospacedDigit().frame(width: 76, alignment: .trailing)
                    }
                    if g.mode == .lower {
                        row("Riduzione", "−\(Int(g.reductionDB)) dB",
                            Binding(get: { g.reductionDB }, set: { v in store.mixer.screamGuard.reductionDB = v.rounded() }), 6...40)
                    }
                    row("Ritorno alla normalità", "\(Int(g.releaseMs)) ms",
                        Binding(get: { g.releaseMs }, set: { v in store.mixer.screamGuard.releaseMs = (v / 50).rounded() * 50 }), 200...3000)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
            .opacity(g.enabled ? 1 : 0.5)
            .allowsHitTesting(g.enabled)
            if g.mode == .lower && g.enabled && Double(store.mixer.currentGainDB) < g.reductionDB {
                Text("La riduzione non può superare il guadagno del microfono (\(store.mixer.currentGainDB) dB): la voce scende al massimo di quel valore.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim).padding(.leading, 4)
            }
        }
    }

    // MARK: State and apply

    private func enabled(_ t: MicEffectTab) -> Binding<Bool> {
        let kp: WritableKeyPath<DSPProfile, Bool> = switch t {
        case .noiseGate: \.noiseGateEnabled
        case .compressor: \.compressorEnabled
        case .equalizer: \.eqEnabled
        case .echo: \.echoEnabled
        case .reverb: \.reverbEnabled
        }
        return Binding(get: { store.dsp[keyPath: kp] }, set: { store.dsp[keyPath: kp] = $0; apply(t) })
    }

    private func dsp(_ kp: WritableKeyPath<DSPProfile, Double>, step: Double = 1) -> Binding<Double> {
        Binding(get: { store.dsp[keyPath: kp] }, set: { store.dsp[keyPath: kp] = ($0 / step).rounded() * step; apply() })
    }

    private func apply(_ tab: MicEffectTab? = nil) {
        applyTask?.cancel()
        // Only the block of the effect being edited is sent (the full set takes a few seconds).
        let tab = tab ?? ui.micTab
        applyTask = Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            switch tab {
            case .reverb, .echo: audio.applyReverb()
            case .equalizer: audio.applyEQ()
            case .noiseGate: audio.applyGate()
            case .compressor: audio.applyCompressor()
            }
        }
    }

    private var matchingPreset: String {
        let g = store.dsp.currentEQ.map(\.gain)
        return EQPreset.all.first { $0.gains == g }?.id ?? "custom"
    }

    /// Measures the mic noise floor for 3 s of silence and puts the gate threshold just above it.
    private func calibrateGate() {
        Task { @MainActor in
            var peak = -120.0
            for s in stride(from: 3, to: 0, by: -1) {
                calibrating = s
                let end = Date().addingTimeInterval(1)
                while Date() < end {
                    peak = max(peak, audio.micInputDB)
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            calibrating = nil
            // Close 3 dB above the hiss, open 6 dB higher: speech is usually 20 dB or more above the noise.
            let close = min(-12, max(-80, (peak + 3).rounded()))
            store.dsp.noiseGateEnabled = true
            store.dsp.noiseGate.closeThreshold = close
            store.dsp.noiseGate.openThreshold = close + 6
            audio.applyGate()
        }
    }

    private func resetTab() {
        let def = DSPProfile(title: "")
        switch ui.micTab {
        case .noiseGate: store.dsp.noiseGate = def.noiseGate
        case .compressor: store.dsp.compressorPresets = def.compressorPresets; store.dsp.makeupGain = def.makeupGain
        case .equalizer: store.dsp.currentEQ = def.eqPresets[0]
        case .echo: store.dsp.echo = def.echo
        case .reverb: store.dsp.reverbPresets = def.reverbPresets
        }
        apply()
    }
}

// MARK: - Meter and graphs

/// Horizontal input meter (−60…0 dB), with an optional gate threshold marker.
private struct LevelMeter: View {
    let db: Double
    let threshold: Double?

    var body: some View {
        GeometryReader { g in
            let f = { (v: Double) in CGFloat(min(1, max(0, (v + 60) / 60))) * g.size.width }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                LinearGradient(stops: [.init(color: .green, location: 0), .init(color: .green, location: 0.7),
                                       .init(color: .yellow, location: 0.85), .init(color: .red, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .mask(alignment: .leading) { Rectangle().frame(width: f(db)) }
                    .clipShape(Capsule())
                if let threshold {
                    Rectangle().fill(Theme.text).frame(width: 2).offset(x: f(threshold) - 1).help("Soglia del noise gate")
                }
            }
        }
    }
}

private struct GraphBackground: View {
    var body: some View { Rectangle().fill(Theme.field) }
}

/// Noise gate: a sketch of speech and noise with the threshold line.
private struct GateGraph: View {
    let threshold: Double
    private let signal: [Double] = [-62, -58, -64, -57, -61, -59, -22, -16, -26, -18, -24, -60, -63, -58, -62, -60]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let y = { (db: Double) in h * CGFloat(min(1, max(0, -db / 80))) }
            ZStack(alignment: .topLeading) {
                GraphBackground()
                Path { p in
                    for (i, v) in signal.enumerated() {
                        let pt = CGPoint(x: w * CGFloat(i) / CGFloat(signal.count - 1), y: y(v))
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                }
                .stroke(Theme.textDim, lineWidth: 1.5)
                Path { p in p.move(to: CGPoint(x: 0, y: y(threshold))); p.addLine(to: CGPoint(x: w, y: y(threshold))) }
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                Text("Soglia \(Int(threshold)) dB").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                    .offset(x: 10, y: max(4, y(threshold) - 18))
                Text("Voce: passa").font(.system(size: 11)).foregroundStyle(.green).offset(x: w * 0.42, y: 8)
                Text("Rumore: tagliato").font(.system(size: 11)).foregroundStyle(Theme.textDim).offset(x: w * 0.75, y: h - 22)
            }
        }
    }
}

/// Compressor transfer curve (input → output).
private struct CompressorGraph: View {
    let threshold: Double
    let ratio: Double

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            // Ratio is stored 0…1: map to 1:1 … 20:1.
            let r = 1 + ratio * 19
            let tx = w * CGFloat((threshold + 60) / 60)
            let ty = h - h * CGFloat((threshold + 60) / 60)
            let out = threshold + (0 - threshold) / r
            let endY = h - h * CGFloat((out + 60) / 60)
            ZStack(alignment: .topLeading) {
                GraphBackground()
                Path { p in p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: 0)) }
                    .stroke(Theme.textFaint, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: tx, y: ty)); p.addLine(to: CGPoint(x: w, y: endY))
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                Circle().fill(Theme.accent).frame(width: 9, height: 9).offset(x: tx - 4.5, y: ty - 4.5)
                Text("Soglia \(Int(threshold)) dB").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent).offset(x: min(tx + 10, w - 110), y: ty + 8)
            }
        }
    }
}

/// Smooth curve through the EQ band gains.
private struct EQGraph: View {
    let gains: [Double]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let pts = gains.enumerated().map { i, v in
                CGPoint(x: w * (CGFloat(i) + 0.5) / CGFloat(gains.count), y: h / 2 - CGFloat(v / 15) * (h / 2 - 12))
            }
            let curve = Path { p in
                guard let first = pts.first else { return }
                p.move(to: CGPoint(x: 0, y: first.y)); p.addLine(to: first)
                for i in 1..<pts.count {
                    let a = pts[i - 1], b = pts[i], mx = (a.x + b.x) / 2
                    p.addCurve(to: b, control1: CGPoint(x: mx, y: a.y), control2: CGPoint(x: mx, y: b.y))
                }
                p.addLine(to: CGPoint(x: w, y: pts.last!.y))
            }
            ZStack(alignment: .topLeading) {
                GraphBackground()
                Path { p in p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2)) }.stroke(Theme.textFaint.opacity(0.5), lineWidth: 1)
                curve.stroke(Theme.accent, lineWidth: 2.5)
                ForEach(Array(zip(["Bassi", "Medi", "Alti"], [0.03, 0.47, 0.92])), id: \.0) { t, x in
                    Text(t).font(.system(size: 10.5)).foregroundStyle(Theme.textDim).offset(x: w * x, y: h - 18)
                }
            }
        }
    }
}
