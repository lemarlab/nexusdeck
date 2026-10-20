import SwiftUI
import WebKit

struct PropertiesPanel: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var editor: DeckEditorModel
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        VStack(spacing: 0) {
            content
        }
    }

    @ViewBuilder private var content: some View {
        if ui.section == .hotkeys {
            if let id = editor.selectedKey, let b = editor.binding(for: id) {
                KeyProperties(key: b)
            } else if let k = editor.selectedKnob {
                PanelHeader(title: "Manopola \(k + 1) - \(store.knob.knobs[k].actionID.map { ActionCatalog.descriptor($0).title } ?? MixerChannel.allCases[k].title)")
                KnobInspector(index: k).padding(.horizontal, 8)
                Spacer(minLength: 0)
            } else {
                Spacer()
                Image(systemName: "square.grid.3x3").font(.system(size: 28)).foregroundStyle(Theme.textFaint)
                Text("Nessun tasto selezionato").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textDim).padding(.top, 6)
                Text("Trascina un'azione dalla libreria su uno spazio libero, oppure clicca un tasto o una manopola per modificarlo.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textFaint).multilineTextAlignment(.center).padding(.horizontal, 30).padding(.top, 2)
                Spacer()
            }
        }
    }
}

struct PanelHeader: View {
    let title: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack {
            Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(2)
            Spacer()
            trailing
        }
        .padding(.horizontal, 16).frame(minHeight: 46)
    }
}

// MARK: - Key properties

struct KeyProperties: View {
    @Binding var key: KeyAssignment
    @EnvironmentObject var editor: DeckEditorModel
    @EnvironmentObject var engine: ActionEngine
    @State private var stateIndex = 0
    @State private var showTextEdit = false

    var body: some View {
        let d = ActionCatalog.descriptor(key.actionID)
        VStack(spacing: 0) {
            PanelHeader(title: "\(categoryTitle(d)) - \(d.title)", trailing: AnyView(
                HStack(spacing: 14) {
                    Button { engine.press(key) } label: { Image(systemName: "play.fill") }.help("Prova azione")
                    Button { editor.delete(key.id) } label: { Image(systemName: "trash") }.help("Elimina")
                }
                .font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(Theme.textDim)))
            // Wide panel under the device: preview on the left, settings on the right.
            HStack(alignment: .top, spacing: 0) {
                previewCard(d)
                    .frame(width: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
                    .padding(.leading, 16).padding(.top, 2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if d.kind != .widget, key.states.indices.contains(stateIndex) {
                            FieldLabel("Titolo")
                            TextField("", text: $key.states[stateIndex].title).darkField().font(.system(size: 12.5, weight: .bold)).frame(maxWidth: .infinity)
                        }
                        if let (p, w) = PackageManager.shared.widget(key.actionID) {
                            if let path = w.propertyViewPath {
                                PackagePropertyView(key: key, url: p.file(path), root: p.directory)
                                    .id(key.id)
                                    .frame(height: 210)
                            } else {
                                Text("Questo widget non ha impostazioni.").font(.system(size: 12)).foregroundStyle(Theme.textDim)
                            }
                        } else {
                            ActionSettingsView(key: $key)
                                .scrollContentBackground(.hidden)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 14)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onChange(of: key.id) { stateIndex = 0 }
    }

    private func previewCard(_ d: ActionDescriptor) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Spacer()
                if d.kind != .widget {
                    Button { showTextEdit.toggle() } label: { Image(systemName: "textformat").font(.system(size: 14, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(Color.white.opacity(0.7))
                        .popover(isPresented: $showTextEdit, arrowEdge: .bottom) { TextEditPopover(style: $key.style) }
                    ImageMenu(state: $key.states[min(stateIndex, key.states.count - 1)])
                }
            }
            .padding(.top, 12).padding(.trailing, 14)
            Spacer()
            Group {
                if d.kind != .widget, key.states.indices.contains(stateIndex) {
                    KeyFaceView(state: key.states[stateIndex], style: key.style)
                } else {
                    WidgetOrKeyView(key: key)
                }
            }
            .frame(width: 75 * CGFloat(min(key.w, 2)), height: 54 * CGFloat(min(key.h, 2)))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
            Spacer()
            if key.states.count > 1 {
                HStack(spacing: 5) {
                    ForEach(key.states.indices, id: \.self) { i in
                        Capsule().fill(i == stateIndex ? Theme.accent : Color.white.opacity(0.2)).frame(width: 26, height: 4)
                            .contentShape(Rectangle().inset(by: -6))
                            .onTapGesture { stateIndex = i }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .background(Color(hex: "#141416"))
    }

    private func categoryTitle(_ d: ActionDescriptor) -> String {
        ActionCatalog.categories.first { $0.actions.contains(d) }?.title ?? "NexusDeck"
    }
}

struct FieldLabel: View {
    let text: LocalizedStringKey
    init(_ t: LocalizedStringKey) { text = t }
    var body: some View { Text(text).font(.system(size: 12.5, weight: .bold)).foregroundStyle(Theme.textMid) }
}

/// Pencil menu: choose an image file, an SF Symbol, or reset.
struct ImageMenu: View {
    @Binding var state: KeyState
    @State private var askSymbol = false
    @State private var symbol = ""

    var body: some View {
        Menu {
            // Same two entries as the reference app, then NexusDeck's extras.
            Button("Seleziona immagine dal disco… (150 × 108 px, PNG, JPG, GIF)") { chooseImage() }
            Divider()
            Button("Simbolo di sistema…") { symbol = state.image.hasPrefix("sf:") ? String(state.image.dropFirst(3)) : ""; askSymbol = true }
            Divider()
            Button("Colore di sfondo…") { pickColor() }
            Button("Rimuovi immagine") { state.image = "" }
        } label: { Image(systemName: "pencil") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .alert("Simbolo SF", isPresented: $askSymbol) {
            TextField("es. headphones", text: $symbol)
            Button("OK") { if !symbol.isEmpty { state.image = "sf:" + symbol } }
            Button("Annulla", role: .cancel) {}
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = UUID().uuidString + "." + (url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased())
        if (try? FileManager.default.copyItem(at: url, to: ProfileStore.iconFolder.appendingPathComponent(name))) != nil { state.image = name }
    }

    private func pickColor() {
        let p = NSColorPanel.shared
        p.color = NSColor(Color(hex: state.background))
        p.makeKeyAndOrderFront(nil)
        ColorPanelBridge.shared.onChange = { state.background = Color(nsColor: $0).hex }
        p.setTarget(ColorPanelBridge.shared)
        p.setAction(#selector(ColorPanelBridge.changed(_:)))
    }
}

final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    var onChange: ((NSColor) -> Void)?
    @objc func changed(_ sender: NSColorPanel) { onChange?(sender.color) }
}

struct TextEditPopover: View {
    @Binding var style: KeyTitleStyle
    private let families = ["", "Helvetica Neue", "Arial", "Avenir Next", "Futura", "Menlo", "Georgia", "Gill Sans", "Impact"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Modifica testo").font(Theme.smallBold)
            HStack {
                DarkPicker(selection: $style.fontFamily, options: families.map { ($0, $0.isEmpty ? "Sistema" : $0) }).frame(width: 150)
                DarkPicker(selection: Binding(get: { Int(style.size) }, set: { style.size = Double($0) }),
                           options: [8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28].map { ($0, "\($0) px") }).frame(width: 80)
            }
            HStack(spacing: 10) {
                toggle("bold", $style.bold)
                toggle("underline", $style.underline)
                toggle("italic", $style.italic)
                Divider().frame(height: 14)
                align("text.alignleft", .leading)
                align("text.aligncenter", .center)
                align("text.alignright", .trailing)
                Divider().frame(height: 14)
                ColorPicker("", selection: Binding(get: { Color(hex: style.colorHex) }, set: { style.colorHex = $0.hex })).labelsHidden()
            }
            Picker("Posizione", selection: $style.alignment) {
                Text("Alto").tag(KeyTitleStyle.Alignment.top)
                Text("Centro").tag(KeyTitleStyle.Alignment.middle)
                Text("Basso").tag(KeyTitleStyle.Alignment.bottom)
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .frame(width: 300)
        .background(Theme.panel)
    }

    private func toggle(_ symbol: String, _ b: Binding<Bool>) -> some View {
        Button { b.wrappedValue.toggle() } label: { Image(systemName: symbol) }
            .buttonStyle(.plain).foregroundStyle(b.wrappedValue ? Theme.accent : Theme.text)
    }

    private func align(_ symbol: String, _ a: KeyTitleStyle.HAlign) -> some View {
        Button { style.textAlignment = a } label: { Image(systemName: symbol) }
            .buttonStyle(.plain).foregroundStyle(style.textAlignment == a ? Theme.accent : Theme.text)
    }
}
