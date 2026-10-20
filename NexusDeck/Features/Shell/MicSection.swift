import SwiftUI

// MARK: - Shared vertical slider card

/// Card with a title, a vertical slider and a numeric field with stepper (as in "Microphone Effects").
struct VSliderCard: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String
    var decimals = 0
    var width: CGFloat = 119
    var height: CGFloat = 300
    var enabled = true

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center).lineLimit(2)
                .frame(height: 40, alignment: .top)
                .padding(.top, 14)
            Spacer(minLength: 8)
            VerticalTrack(value: $value, range: range, step: step)
                .frame(width: 24, height: 160)
            Spacer(minLength: 10)
            HStack(spacing: 4) {
                Text(decimals == 0 ? "\(Int(value.rounded()))" : String(format: "%.\(decimals)f", value))
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .frame(width: 50, height: 24).background(Theme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(spacing: 2) {
                    Button { value = min(range.upperBound, value + step) } label: { Image(systemName: "arrowtriangle.up.fill") }
                    Button { value = max(range.lowerBound, value - step) } label: { Image(systemName: "arrowtriangle.down.fill") }
                }
                .font(.system(size: 7)).buttonStyle(.plain).foregroundStyle(Theme.textDim)
                Text(unit).font(.system(size: 10)).foregroundStyle(Theme.textDim).frame(width: 20, alignment: .leading)
            }
            .padding(.bottom, 14)
        }
        .frame(width: width, height: height)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
    }
}

struct VerticalTrack: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        GeometryReader { g in
            let f = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.track).frame(width: 5)
                Capsule().fill(Theme.accent).frame(width: 5, height: max(0, g.size.height * f))
                Circle().fill(.white).frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .offset(y: -g.size.height * f + 9)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let p = 1 - min(max(v.location.y / g.size.height, 0), 1)
                let raw = range.lowerBound + Double(p) * (range.upperBound - range.lowerBound)
                value = (raw / step).rounded() * step
            })
        }
    }
}

// MARK: - Column

struct MicColumn: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @State private var confirm48V = false
    @State private var renaming = false
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Text("Microfono").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textFaint).textCase(.uppercase)
                    Spacer()
                    Button { chooseImage() } label: { Image(systemName: "photo.on.rectangle") }.help("Immagine del microfono")
                    Button { name = store.mixer.micName; renaming = true } label: { Image(systemName: "pencil") }.help("Rinomina microfono")
                }
                .font(.system(size: 13)).buttonStyle(.plain).foregroundStyle(Theme.textDim)
                .padding(.horizontal, 14).frame(height: 40)
                micImage.frame(height: 144).padding(.top, 4)
                Text(store.mixer.micName).font(.system(size: 14, weight: .semibold)).padding(.top, 14).padding(.bottom, 20)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Tipo di microfono").font(.system(size: 12)).foregroundStyle(Theme.textMid)
                DarkPicker(selection: Binding(get: { store.mixer.micType }, set: { t in
                    if t == .xlrCondenser && !store.mixer.phantom48V { confirm48V = true } else { store.mixer.micType = t; audio.applyMic() }
                }), options: MicType.allCases.map { ($0, $0.title) }, height: 29)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            VStack {
                VSliderCard(title: "Guadagno",
                            value: Binding(get: { Double(store.mixer.currentGainDB) }, set: { store.mixer.currentGainDB = Int($0); audio.applyMic() }),
                            range: 0...Double(MicGain.maxDB), unit: "dB", height: 299)
                    .padding(.top, 16)
                Spacer()
            }
            .frame(maxWidth: .infinity)
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

    @ViewBuilder private var micImage: some View {
        if !store.mixer.micImage.isEmpty, let img = ImageCache.image(at: ProfileStore.iconFolder.appendingPathComponent(store.mixer.micImage)) {
            Image(nsImage: img).resizable().scaledToFit()
        } else {
            MicIllustration()
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let n = "mic-" + UUID().uuidString + "." + url.pathExtension
        if (try? FileManager.default.copyItem(at: url, to: ProfileStore.iconFolder.appendingPathComponent(n))) != nil { store.mixer.micImage = n }
    }
}

/// Our own drawing of a broadcast microphone on a yoke mount.
/// Microphone artwork: an app-icon style tile with the SF Symbol microphone.
struct MicIllustration: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(LinearGradient(colors: [Color(hex: "#FFB340"), Color(hex: "#FF7A00")], startPoint: .top, endPoint: .bottom))
            .frame(width: 96, height: 96)
            .overlay(Image(systemName: "mic.fill").font(.system(size: 44, weight: .medium)).foregroundStyle(.white))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Color(hex: "#FF7A00").opacity(0.4), radius: 10, y: 5)
            .frame(width: 140, height: 130)
    }
}

// MARK: - Effects panel

struct MicEffectsPanel: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @State private var applyTask: Task<Void, Never>?

    @State private var calibrating: Int?

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

    private func apply() {
        applyTask?.cancel()
        // Only the block of the effect being edited is sent, right away (the full set takes a few seconds).
        let tab = ui.micTab
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

    private func dsp<T>(_ kp: WritableKeyPath<DSPProfile, T>) -> Binding<T> {
        Binding(get: { store.dsp[keyPath: kp] }, set: { store.dsp[keyPath: kp] = $0; apply() })
    }

    var body: some View {
        GeometryReader { g in
            VStack(alignment: .leading, spacing: 0) {
                tabs.padding(.top, 4)
                header.padding(.horizontal, 6).frame(height: 66)
                Spacer(minLength: 0)
                content.frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text("Se l'audio mixato con gli effetti suona male, prova a ridurre guadagno o livelli degli effetti.")
                }
                .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                .padding(.leading, 6).padding(.bottom, 6)
            }
            .frame(width: max(600, g.size.width - 56), height: max(500, g.size.height - 48))
            .padding(.leading, 28).padding(.top, 24)
        }
    }

    private var tabs: some View {
        // Effect chain: one segment per block, a dot shows which effects are on.
        HStack(spacing: 2) {
            ForEach(MicEffectTab.allCases) { t in
                let on = ui.micTab == t
                Button { withAnimation(.easeOut(duration: 0.12)) { ui.micTab = t } } label: {
                    HStack(spacing: 6) {
                        Circle().fill(effectOn(t) ? Theme.accent : Theme.track).frame(width: 7, height: 7)
                        Text(t.title).font(.system(size: 12.5, weight: on ? .semibold : .regular))
                    }
                    .foregroundStyle(on ? Theme.text : Theme.textDim)
                    .frame(maxWidth: .infinity).frame(height: 28)
                    .background(on ? Theme.card : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 0.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func effectOn(_ t: MicEffectTab) -> Bool {
        switch t {
        case .noiseGate: store.dsp.noiseGateEnabled
        case .compressor: store.dsp.compressorEnabled
        case .equalizer: store.dsp.eqEnabled
        case .echo: store.dsp.echoEnabled
        case .reverb: store.dsp.reverbEnabled
        }
    }

    private var enabledBinding: Binding<Bool> {
        switch ui.micTab {
        case .noiseGate: dsp(\.noiseGateEnabled)
        case .compressor: dsp(\.compressorEnabled)
        case .equalizer: dsp(\.eqEnabled)
        case .echo: dsp(\.echoEnabled)
        case .reverb: dsp(\.reverbEnabled)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            PillToggle(isOn: enabledBinding)
            Text(ui.micTab.title).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabledBinding.wrappedValue ? Theme.text : Theme.textDim)
            Spacer()
            if ui.micTab == .noiseGate {
                if let left = calibrating {
                    ProgressView().controlSize(.small)
                    Text("Resta in silenzio… \(left)").font(.system(size: 12)).foregroundStyle(Theme.textMid)
                } else {
                    FlatButton(title: "Calibra", width: 90) { calibrateGate() }
                        .help("Misura il fruscio del microfono in 3 secondi di silenzio e imposta la soglia appena sopra.")
                }
            }
            if ui.micTab == .equalizer {
                Image(systemName: "waveform").foregroundStyle(Theme.textMid)
                DarkPicker(selection: Binding(get: { matchingPreset }, set: { id in
                    if let p = EQPreset.all.first(where: { $0.id == id }) {
                        var eq = store.dsp.currentEQ
                        for i in eq.indices { eq[i].gain = p.gains[i] }
                        store.dsp.currentEQ = eq; apply()
                    }
                }), options: [("custom", "Personalizzato")] + EQPreset.all.map { ($0.id, $0.title) }).frame(width: 280)
            }
            if ui.micTab == .reverb {
                Image(systemName: "waveform").foregroundStyle(Theme.textMid)
                DarkPicker(selection: dsp(\.reverbPresetIndex), options: [(0, "Stanza piccola"), (1, "Spazio piccolo"), (2, "Sala"), (3, "Spazio ampio")]).frame(width: 280)
            }
            Button { resetTab() } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 14)) }
                .buttonStyle(.plain).foregroundStyle(Theme.textDim).help("Ripristina")
        }
    }

    @ViewBuilder private var content: some View {
        let on = enabledBinding.wrappedValue
        switch ui.micTab {
        case .noiseGate:
            HStack(spacing: 8) {
                // One threshold, as in the reference app: the gate closes 6 dB below where it opens.
                VSliderCard(title: "Soglia", value: Binding(get: { store.dsp.noiseGate.openThreshold }, set: {
                    store.dsp.noiseGate.openThreshold = $0
                    store.dsp.noiseGate.closeThreshold = $0 - 6
                    apply()
                }), range: -80...0, unit: "dB", enabled: on)
                VSliderCard(title: "Tempo di\nattacco", value: dsp(\.noiseGate.attack), range: 0...100, unit: "ms", enabled: on)
                VSliderCard(title: "Tempo di\nmantenimento", value: dsp(\.noiseGate.hold), range: 0...500, unit: "ms", enabled: on)
                VSliderCard(title: "Tempo di\nrilascio", value: dsp(\.noiseGate.release), range: 0...2000, step: 10, unit: "ms", enabled: on)
            }
        case .compressor:
            let i = store.dsp.compressorPresetIndex
            HStack(spacing: 8) {
                VSliderCard(title: "Soglia", value: dsp(\.compressorPresets[i].threshold), range: -60...0, unit: "dB", enabled: on)
                VSliderCard(title: "Rapporto", value: Binding(get: { store.dsp.compressorPresets[i].ratio * 100 }, set: { store.dsp.compressorPresets[i].ratio = $0 / 100; apply() }),
                            range: 0...100, unit: "%", enabled: on)
                VSliderCard(title: "Tempo di\nattacco", value: dsp(\.compressorPresets[i].attack), range: 1...200, unit: "ms", enabled: on)
                VSliderCard(title: "Tempo di\nrilascio", value: dsp(\.compressorPresets[i].release), range: 1...1000, unit: "ms", enabled: on)
                VSliderCard(title: "Guadagno\nin uscita", value: dsp(\.makeupGain), range: 0...24, unit: "dB", enabled: on)
            }
        case .equalizer:
            HStack(alignment: .top, spacing: 0) {
                eqGroup("BASSI", 0...2)
                Rectangle().fill(Theme.separator).frame(width: 1, height: 340)
                eqGroup("MEDI", 3...5)
                Rectangle().fill(Theme.separator).frame(width: 1, height: 340)
                eqGroup("ALTI", 6...7)
            }
            .opacity(on ? 1 : 0.45).allowsHitTesting(on)
        case .echo:
            HStack(spacing: 8) {
                VSliderCard(title: "Livello", value: dsp(\.echo.gain), range: -40...0, unit: "dB", enabled: on)
                VSliderCard(title: "Tempo", value: dsp(\.echo.time), range: 1...10, unit: "s", enabled: on)
                VSliderCard(title: "Ritardo", value: dsp(\.echo.delay), range: 10...270, unit: "ms", enabled: on)
            }
        case .reverb:
            let i = store.dsp.reverbPresetIndex
            HStack(spacing: 8) {
                VSliderCard(title: "Livello", value: dsp(\.reverbPresets[i].gain), range: -40...0, unit: "dB", enabled: on)
                VSliderCard(title: "Tempo", value: dsp(\.reverbPresets[i].time), range: 1...10, unit: "s", enabled: on)
                VSliderCard(title: "Dimensione\nstanza", value: dsp(\.reverbPresets[i].roomSize), range: 1...40, step: 0.01, unit: "m³", decimals: 2, enabled: on)
                VSliderCard(title: "Smorzamento", value: Binding(get: { store.dsp.reverbPresets[i].damp * 100 }, set: { store.dsp.reverbPresets[i].damp = $0 / 100; apply() }),
                            range: 0...100, unit: "%", enabled: on)
                VSliderCard(title: "Diffusione", value: Binding(get: { store.dsp.reverbPresets[i].diffusion * 100 }, set: { store.dsp.reverbPresets[i].diffusion = $0 / 100; apply() }),
                            range: 0...100, unit: "%", enabled: on)
            }
        }
    }

    private func eqGroup(_ title: String, _ r: ClosedRange<Int>) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
            Rectangle().fill(Theme.accent).frame(height: 3)
            HStack(spacing: 8) {
                ForEach(Array(r), id: \.self) { i in
                    let b = store.dsp.currentEQ[i]
                    VSliderCard(title: "\(Int(b.frequency)) Hz",
                                value: Binding(get: { b.gain }, set: { var eq = store.dsp.currentEQ; eq[i].gain = $0; store.dsp.currentEQ = eq; apply() }),
                                range: -15...15, unit: "dB", width: 79)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var matchingPreset: String {
        let g = store.dsp.currentEQ.map(\.gain)
        return EQPreset.all.first { $0.gains == g }?.id ?? "custom"
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
