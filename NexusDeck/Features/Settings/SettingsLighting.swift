import SwiftUI
import ServiceManagement

// MARK: Custom lighting

enum LightingArea: String { case screen, keys, knobs, strip }

struct CustomLightingPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var deck: DeckController
    @State private var area: LightingArea = .screen

    private func dev<T>(_ kp: WritableKeyPath<DeviceSettings, T>, _ apply: @escaping () -> Void = {}) -> Binding<T> {
        Binding(get: { store.library.device[keyPath: kp] }, set: { store.library.device[keyPath: kp] = $0; apply() })
    }

    var body: some View {
        LightingDeviceDrawing(area: $area, stripHex: store.library.device.ledAura.colorHex, knobHex: store.library.device.ledKnob.colorSource == .perItem ? store.library.device.ledKnob.itemColors[0] : store.library.device.ledKnob.colorHex)
            .frame(maxWidth: .infinity).padding(.bottom, 10)
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textMid)
                Spacer()
                Button { reset() } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.plain).foregroundStyle(Theme.textDim)
            }
            switch area {
            case .screen: screenSettings
            case .keys: LEDControls(led: dev(\.ledButton, { audio.applyLEDs() }), zone: .keys)
            case .knobs: LEDControls(led: dev(\.ledKnob, { audio.applyLEDs() }), zone: .knobs)
            case .strip: LEDControls(led: dev(\.ledAura, { audio.applyLEDs() }), zone: .strip)
            }
        }
        .padding(.horizontal, 40).padding(.vertical, 18)
        .background(Theme.card)
    }

    private var title: LocalizedStringKey {
        switch area {
        case .screen: "Schermo touch"
        case .keys: "Tasti funzione"
        case .knobs: "Manopole"
        case .strip: "Luce ambiente"
        }
    }

    @ViewBuilder private var screenSettings: some View {
        SettingRow(title: "Spegni dopo", info: "Lo schermo si spegne dopo questo tempo di inattività. Toccalo per riaccenderlo.", labelWidth: 150) {
            DarkPicker(selection: dev(\.powerSavingMinutes, { audio.applyScreen() }),
                       options: [(0, "Mai"), (1, "1 minuto"), (5, "5 minuti"), (10, "10 minuti"), (20, "20 minuti"), (30, "30 minuti"), (60, "1 ora")], height: 26).frame(width: 312)
        }
        SettingRow(title: "Luminosità", labelWidth: 150) {
            Image(systemName: "sun.min").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            ThinSlider(value: Binding(get: { Double(store.library.device.brightness) }, set: { store.library.device.brightness = Int($0) }), range: 1...100) { audio.applyScreen() }
                .frame(width: 236)
            Image(systemName: "sun.max").font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        SettingRow(title: "Opacità tasti", info: "Trasparenza dei tasti sopra lo sfondo dello schermo.", labelWidth: 150) {
            Image(systemName: "circle.dotted").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            ThinSlider(value: Binding(get: { store.library.device.panelOpacity * 100 }, set: { store.library.device.panelOpacity = $0 / 100; deck.needsRedraw.send() }))
                .frame(width: 236)
            Image(systemName: "circle.fill").font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        SettingRow(title: "Griglia", labelWidth: 150) {
            Toggle("Nascondi la griglia delle caselle vuote", isOn: dev(\.autoHideGrid, { deck.needsRedraw.send() }))
                .toggleStyle(.checkbox).font(.system(size: 13)).fixedSize()
        }
        SettingRow(title: "Effetti al tocco", labelWidth: 150) {
            Toggle("Rimpicciolisci il tasto quando lo tocchi", isOn: dev(\.touchEffect)).toggleStyle(.checkbox).font(.system(size: 13)).fixedSize()
        }
        SettingRow(title: "Sfondo", labelWidth: 150) {
            DarkPicker(selection: dev(\.background.mode, { deck.needsRedraw.send() }), options: [(.color, "Colore pieno"), (.image, "Immagine")], height: 26).frame(width: 312)
        }
        if store.library.device.background.mode == .color {
            SettingRow(title: "", labelWidth: 150) {
                SwatchRow(hex: Binding(get: { store.library.device.background.colorHex }, set: { store.library.device.background.colorHex = $0; deck.needsRedraw.send() }), first: "#111111")
            }
        } else {
            SettingRow(title: "Adattamento", labelWidth: 150) {
                DarkPicker(selection: dev(\.background.displayMode, { deck.needsRedraw.send() }), options: BackgroundSetting.displayModes, height: 26).frame(width: 312)
            }
            SettingRow(title: "", labelWidth: 150) {
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { i in
                        let recent = store.library.device.background.recent
                        let path = i < recent.count ? recent[i] : ""
                        Button {
                            if path.isEmpty { pickBackground() } else { store.library.device.background.use(path); deck.needsRedraw.send() }
                        } label: {
                            ZStack {
                                Theme.field
                                if let img = ImageCache.image(atPath: path) { Image(nsImage: img).resizable().scaledToFill() }
                                else { Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(Theme.textDim) }
                            }
                            .frame(width: 50, height: 30).clipped()
                            .overlay(Rectangle().strokeBorder(path == store.library.device.background.imagePath && !path.isEmpty ? Theme.accent : Color.white.opacity(0.12), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            SettingRow(title: "", labelWidth: 150) {
                FlatButton(title: "Scegli immagine…", width: 150) { pickBackground() }
                Text("800 × 480 px · PNG, JPG").font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
        }
    }

    private func pickBackground() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg]
        guard p.runModal() == .OK, let u = p.url else { return }
        let dst = ProfileStore.iconFolder.appendingPathComponent("background-\(UUID().uuidString.prefix(8))." + u.pathExtension)
        try? FileManager.default.copyItem(at: u, to: dst)
        store.library.device.background.use(dst.path)
        deck.needsRedraw.send()
    }

    private func reset() {
        let d = DeviceSettings()
        switch area {
        case .screen:
            store.library.device.brightness = d.brightness; store.library.device.powerSavingMinutes = d.powerSavingMinutes
            store.library.device.panelOpacity = d.panelOpacity; store.library.device.autoHideGrid = d.autoHideGrid
            store.library.device.touchEffect = d.touchEffect; store.library.device.background = d.background
            audio.applyScreen(); deck.needsRedraw.send()
        case .keys: store.library.device.ledButton = d.ledButton; audio.applyLEDs()
        case .knobs: store.library.device.ledKnob = d.ledKnob; audio.applyLEDs()
        case .strip: store.library.device.ledAura = d.ledAura; audio.applyLEDs()
        }
    }
}

/// Lighting controls for one zone, always in the same order:
/// Effect → Brightness → Speed (animated effects) → Color (effects that use one, with a per-zone color source).
struct LEDControls: View {
    enum Zone { case keys, knobs, strip, status }

    @Binding var led: LEDSetting
    let zone: Zone
    @State private var editing = 0

    private var modes: [LEDSetting.Mode] {
        switch zone {
        case .keys: [.off, .staticColor]
        case .knobs: [.off, .staticColor, .flash, .rainbow, .volume]
        case .strip: [.off, .staticColor, .flash, .rainbow, .wave, .colorCycle, .spectrum]
        case .status: [.staticColor, .flash, .rainbow]
        }
    }

    private var sources: [(LEDSetting.ColorSource, String)] {
        switch zone {
        case .keys: [(.widget, "Colore del widget"), (.single, "Uguale per tutti"), (.perItem, "Diverso per ogni tasto")]
        case .knobs: [(.single, "Uguale per tutte"), (.perItem, "Diverso per ogni manopola")]
        default: []
        }
    }

    private var itemNames: [String] {
        zone == .keys ? ["Alto sx", "Alto dx", "Basso sx", "Basso dx"] : ["Mic", "Line In", "Console", "System", "Game", "Chat"]
    }

    /// Color source actually used by this zone.
    private var source: LEDSetting.ColorSource {
        sources.contains { $0.0 == led.colorSource } ? led.colorSource : .single
    }

    var body: some View {
        SettingRow(title: "Effetto", labelWidth: 150) {
            DarkPicker(selection: $led.mode, options: modes.map { ($0, title($0)) }, height: 26).frame(width: 312)
        }
        if led.mode != .off {
            SettingRow(title: "Luminosità", labelWidth: 150) {
                Image(systemName: "sun.min").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                ThinSlider(value: Binding(get: { Double(led.brightness) }, set: { led.brightness = Int($0) })).frame(width: 236)
                Image(systemName: "sun.max").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
        }
        if led.mode.usesSpeed {
            SettingRow(title: "Velocità", labelWidth: 150) {
                Image(systemName: "tortoise").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                ThinSlider(value: Binding(get: { Double(led.speed) }, set: { led.speed = Int($0) }), range: 0...10).frame(width: 236)
                Image(systemName: "hare").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
        }
        if led.mode == .volume {
            SettingRow(title: "Misuratore di picco", info: "Gli anelli mostrano il livello audio in tempo reale invece del volume impostato.", labelWidth: 150) {
                Toggle("Attivo", isOn: $led.peak).toggleStyle(.checkbox).font(.system(size: 13))
            }
        }
        if led.mode.usesColor {
            colorSection
        } else if led.mode != .off {
            SettingRow(title: "Colore", labelWidth: 150) {
                Text("Questo effetto usa colori automatici.").font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
        }
    }

    @ViewBuilder private var colorSection: some View {
        if !sources.isEmpty {
            SettingRow(title: "Colore", labelWidth: 150) {
                DarkPicker(selection: Binding(get: { source }, set: { led.colorSource = $0 }), options: sources, height: 26).frame(width: 312)
            }
        }
        switch source {
        case .widget:
            SettingRow(title: "", labelWidth: 150) {
                Text("Ogni tasto prende il colore di sfondo del widget assegnato. I tasti vuoti restano spenti.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textDim).frame(width: 312, alignment: .leading)
            }
        case .single:
            SettingRow(title: sources.isEmpty ? "Colore" : "", labelWidth: 150) { SwatchRow(hex: $led.colorHex) }
        case .perItem:
            SettingRow(title: "", labelWidth: 150) {
                HStack(spacing: 8) {
                    ForEach(itemNames.indices, id: \.self) { i in
                        VStack(spacing: 4) {
                            Circle().fill(Color(hex: led.itemColors[i])).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(editing == i ? Theme.accent : Color.white.opacity(0.25), lineWidth: editing == i ? 2 : 1))
                            Text(itemNames[i]).font(.system(size: 10)).foregroundStyle(editing == i ? Theme.text : Theme.textDim)
                        }
                        .frame(width: 50)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = i }
                    }
                    ColorPicker("", selection: Binding(get: { Color(hex: led.itemColors[editing]) }, set: { led.itemColors[editing] = $0.hex }), supportsOpacity: false)
                        .labelsHidden()
                }
            }
            SettingRow(title: "", labelWidth: 150) {
                SwatchRow(hex: Binding(get: { led.itemColors[min(editing, itemNames.count - 1)] }, set: { led.itemColors[min(editing, itemNames.count - 1)] = $0 }))
            }
        }
    }

    private func title(_ m: LEDSetting.Mode) -> String {
        switch m {
        case .off: "Spento"
        case .staticColor: zone == .keys ? "Acceso" : "Statico"
        case .breathing: "Statico"
        case .flash: "Pulsante"
        case .rainbow: "Respiro"
        case .wave: "Arcobaleno"
        case .colorCycle: "Ciclo colori"
        case .spectrum: "Onda colori"
        case .volume: "Livello volume"
        }
    }
}

struct LightingDeviceDrawing: View {
    @Binding var area: LightingArea
    let stripHex: String
    let knobHex: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#3A3A3A")).frame(width: 414, height: 270)
                Text("NexusDeck").font(.system(size: 12, weight: .heavy)).italic().offset(x: 320, y: 16)
                // Screen
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(hex: "#2A2A2A"))
                    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                        ForEach(0..<4, id: \.self) { _ in GridRow { ForEach(0..<5, id: \.self) { _ in Rectangle().fill(Color(hex: "#1E1E1E")) } } }
                    }
                    .padding(22)
                }
                .frame(width: 240, height: 162)
                .overlay(corners(area == .screen))
                .offset(x: 10, y: 30)
                .onTapGesture { area = .screen }
                // Keys
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(0..<2, id: \.self) { _ in GridRow { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 6).fill(Color.black).frame(width: 50, height: 62) } } }
                }
                .padding(10)
                .overlay(corners(area == .keys))
                .offset(x: 272, y: 38)
                .onTapGesture { area = .keys }
                // Knobs
                HStack(spacing: 18) {
                    ForEach(0..<6, id: \.self) { _ in
                        Circle().fill(Color(hex: "#1A1A1A")).frame(width: 50, height: 50)
                            .overlay(Circle().strokeBorder(Color(hex: knobHex), style: StrokeStyle(lineWidth: 3, dash: [5, 3])).padding(2))
                    }
                }
                .padding(6)
                .overlay(corners(area == .knobs))
                .offset(x: 10, y: 205)
                .onTapGesture { area = .knobs }
            }
            .frame(width: 414, height: 270)
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#2E2E2E")).frame(width: 420, height: 40)
                Rectangle().fill(area == .strip ? AnyShapeStyle(Color(hex: stripHex))
                                 : AnyShapeStyle(LinearGradient(colors: [.green, .cyan, .blue, .purple, .pink, .red, .orange, .yellow, .green], startPoint: .leading, endPoint: .trailing)))
                    .frame(width: 420, height: 3).offset(y: 2)
            }
            .overlay(HStack { Rectangle().fill(area == .strip ? Theme.accent : Color(hex: "#555")).frame(width: 2, height: 46); Spacer(); Rectangle().fill(area == .strip ? Theme.accent : Color(hex: "#555")).frame(width: 2, height: 46) }.frame(width: 446))
            .padding(.top, 20)
            .onTapGesture { area = .strip }
        }
    }

    private func corners(_ on: Bool) -> some View {
        GeometryReader { g in
            let c = on ? Theme.accent : Color(hex: "#555555")
            Path { p in
                let w = g.size.width, h = g.size.height, l: CGFloat = 10
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: 0, y: h - l)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: l, y: h))
                p.move(to: CGPoint(x: w - l, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - l))
            }
            .stroke(c, lineWidth: 3)
        }
    }
}
