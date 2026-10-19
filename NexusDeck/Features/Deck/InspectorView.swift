import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    @EnvironmentObject var editor: DeckEditorModel
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        Group {
            if let id = editor.selectedKey, let binding = editor.binding(for: id) {
                KeyInspector(key: binding)
            } else if let k = editor.selectedKnob {
                KnobInspector(index: k)
            } else {
                ContentUnavailableView("Nessuna selezione", systemImage: "cursorarrow.click", description: Text("Seleziona un tasto, un widget o una manopola per modificarne le proprietà."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct KeyInspector: View {
    @Binding var key: KeyAssignment
    @EnvironmentObject var editor: DeckEditorModel
    @EnvironmentObject var engine: ActionEngine
    @State private var stateTab = 0

    var body: some View {
        let d = ActionCatalog.descriptor(key.actionID)
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(d.title, systemImage: d.symbol).font(.headline)
                    Spacer()
                    Button("Prova") { engine.press(key) }
                    Button(role: .destructive) { editor.delete(key.id) } label: { Image(systemName: "trash") }
                }
                if d.kind != .widget {
                    if key.states.count > 1 {
                        Picker("Stato", selection: $stateTab) {
                            ForEach(key.states.indices, id: \.self) { Text("Stato \($0 + 1)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if key.states.indices.contains(stateTab) {
                        StateEditor(state: $key.states[stateTab], style: $key.style)
                    }
                }
            }
            .frame(width: 360)
            Divider()
            ScrollView {
                ActionSettingsView(key: $key)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .onChange(of: key.id) { stateTab = 0 }
    }
}

struct StateEditor: View {
    @Binding var state: KeyState
    @Binding var style: KeyTitleStyle
    @State private var symbolName = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KeyFaceView(state: state, style: style)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Form {
                TextField("Titolo", text: $state.title)
                HStack {
                    ColorPicker("Sfondo", selection: Binding(get: { Color(hex: state.background) }, set: { state.background = $0.hex }))
                    ColorPicker("Testo", selection: Binding(get: { Color(hex: style.colorHex) }, set: { style.colorHex = $0.hex }))
                }
                HStack {
                    Stepper("Dim. \(Int(style.size))", value: $style.size, in: 8...28)
                    Toggle("G", isOn: $style.bold).toggleStyle(.button)
                    Toggle("C", isOn: $style.italic).toggleStyle(.button)
                    Toggle("S", isOn: $style.underline).toggleStyle(.button)
                }
                Picker("Posizione testo", selection: $style.alignment) {
                    Text("Alto").tag(KeyTitleStyle.Alignment.top)
                    Text("Centro").tag(KeyTitleStyle.Alignment.middle)
                    Text("Basso").tag(KeyTitleStyle.Alignment.bottom)
                }
                HStack {
                    Button("Immagine…") { chooseImage() }
                    TextField("SF Symbol", text: $symbolName).onSubmit { if !symbolName.isEmpty { state.image = "sf:" + symbolName } }
                    Button { state.image = "" } label: { Image(systemName: "xmark.circle") }.help("Rimuovi immagine")
                }
            }
            .formStyle(.columns)
        }
        .onAppear { symbolName = state.image.hasPrefix("sf:") ? String(state.image.dropFirst(3)) : "" }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .svg, .heic, .image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = UUID().uuidString + "." + (url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased())
        do {
            try FileManager.default.copyItem(at: url, to: ProfileStore.iconFolder.appendingPathComponent(name))
            state.image = name
        } catch {}
    }
}

struct KnobInspector: View {
    let index: Int
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        let channel = MixerChannel.allCases[index]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Manopola \(index + 1)", systemImage: "dial.medium").font(.headline)
                Spacer()
                if store.knob.knobs[index].actionID != nil {
                    Button("Ripristina canale mixer") { store.knob.knobs[index].actionID = nil; store.knob.knobs[index].settings = [:] }
                }
            }
            DropdownRowField(title: "Funzione", selection: Binding(get: { store.knob.knobs[index].actionID ?? "" }, set: { store.knob.knobs[index].actionID = $0.isEmpty ? nil : $0 }),
                             options: [("", "Canale mixer: \(channel.title)")] + ActionCatalog.categories.flatMap(\.actions).filter { $0.kind == .knob }.map { ($0.id, $0.title) })
            .frame(maxWidth: 420)
            if let id = store.knob.knobs[index].actionID {
                KnobSettingsView(actionID: id, settings: Binding(get: { store.knob.knobs[index].settings }, set: { store.knob.knobs[index].settings = $0 }))
            } else {
                Text("Ruota: volume del canale \(channel.title) nel mix attivo. Premi: muto.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }
}
