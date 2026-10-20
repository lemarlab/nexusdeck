import SwiftUI
import UniformTypeIdentifiers

private let cell: CGFloat = 92
private let gap: CGFloat = 8

struct DeckEditorView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var editor: DeckEditorModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                ProfileBar()
                Divider()
                ScrollView {
                    VStack(spacing: 18) {
                        HStack(alignment: .top, spacing: 24) {
                            FunctionKeysView()
                            PanelGridView()
                        }
                        PageBar()
                        KnobRowView()
                    }
                    .padding(24)
                }
                Divider()
                InspectorView()
                    .frame(height: 280)
            }
            .frame(minWidth: 760)
            ActionLibraryView()
                .frame(minWidth: 240, idealWidth: 270, maxWidth: 340)
        }
        .alert(editor.message ?? "", isPresented: Binding(get: { editor.message != nil }, set: { if !$0 { editor.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .navigationTitle("Tasti e widget")
    }
}

// MARK: - Profile bar

struct ProfileBar: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var editor: DeckEditorModel
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        HStack {
            Image(systemName: "square.grid.3x3")
            Picker("Profilo", selection: Binding(get: { store.hotkey.id }, set: { editor.activate($0) })) {
                ForEach(store.library.hotkeyProfiles) { Text($0.title).tag($0.id) }
            }
            .frame(maxWidth: 300)
            Menu {
                Button("Nuovo profilo") { editor.newProfile() }
                Button("Duplica") { editor.duplicateProfile() }
                Button("Rinomina…") { newName = store.hotkey.title; renaming = true }
                Divider()
                Button("Importa…") { importProfile() }
                Button("Esporta…") { exportProfile() }
                Divider()
                Button("Elimina", role: .destructive) { editor.deleteProfile() }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
        .padding(10)
        .alert("Rinomina profilo", isPresented: $renaming) {
            TextField("Nome", text: $newName)
            Button("OK") { if !newName.isEmpty { store.hotkey.title = newName } }
            Button("Annulla", role: .cancel) {}
        }
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.nexusProfile]
        panel.nameFieldStringValue = store.hotkey.title
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.exportHotkeyProfile(store.hotkey, to: url) } catch { editor.message = error.localizedDescription }
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.nexusProfile, .json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.importProfile(from: url) } catch { editor.message = "File non valido: \(error.localizedDescription)" }
        }
    }
}

extension UTType {
    static let nexusProfile = UTType(exportedAs: "com.nexusdeck.lemarlab.profile", conformingTo: .json)
}

// MARK: - Panel

struct PanelGridView: View {
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var editor: DeckEditorModel

    var body: some View {
        let keys = deck.keys(onPage: deck.currentPage)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14).fill(Color.black)
                .frame(width: CGFloat(editor.columns) * (cell + gap) + gap, height: CGFloat(editor.rows) * (cell + gap) + gap)
            ForEach(0..<editor.rows, id: \.self) { y in
                ForEach(0..<editor.columns, id: \.self) { x in
                    EmptySlot(x: x, y: y, slot: .touch)
                        .offset(x: gap + CGFloat(x) * (cell + gap), y: gap + CGFloat(y) * (cell + gap))
                }
            }
            ForEach(keys) { k in
                KeyCell(key: k)
                    .frame(width: CGFloat(k.w) * cell + CGFloat(k.w - 1) * gap, height: CGFloat(k.h) * cell + CGFloat(k.h - 1) * gap)
                    .offset(x: gap + CGFloat(k.x) * (cell + gap), y: gap + CGFloat(k.y) * (cell + gap))
            }
        }
    }
}

struct FunctionKeysView: View {
    @EnvironmentObject var deck: DeckController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tasti funzione").font(.caption).foregroundStyle(.secondary)
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                ForEach(0..<2, id: \.self) { y in
                    GridRow {
                        ForEach(0..<2, id: \.self) { x in
                            if let k = deck.key(at: x, y, page: 0, slot: .functionKey) {
                                KeyCell(key: k).frame(width: 64, height: 64)
                            } else {
                                EmptySlot(x: x, y: y, slot: .functionKey, size: 64)
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
        }
    }
}

struct EmptySlot: View {
    @EnvironmentObject var editor: DeckEditorModel
    let x: Int, y: Int, slot: SlotKind
    var size: CGFloat = cell
    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
            .foregroundStyle(targeted ? Color.accentColor : Color.gray.opacity(0.4))
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(targeted ? 0.1 : 0.03)))
            .frame(width: size, height: size)
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first else { return false }
                if item.hasPrefix("key:"), let id = UUID(uuidString: String(item.dropFirst(4))) {
                    return editor.move(keyID: id, x: x, y: y, slot: slot)
                }
                return editor.drop(actionID: item, x: x, y: y, slot: slot)
            } isTargeted: { targeted = $0 }
    }
}

struct KeyCell: View {
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var editor: DeckEditorModel
    @EnvironmentObject var engine: ActionEngine
    let key: KeyAssignment

    var body: some View {
        WidgetOrKeyView(key: key)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(editor.selectedKey == key.id ? Color.accentColor : .clear, lineWidth: 3))
            .contentShape(Rectangle())
            .onTapGesture { editor.selectedKey = key.id; editor.selectedKnob = nil }
            .onTapGesture(count: 2) { engine.press(key) }
            .draggable("key:\(key.id.uuidString)")
            .contextMenu {
                Button("Esegui") { engine.press(key) }
                Button("Duplica") { editor.duplicate(key.id) }
                Button("Elimina", role: .destructive) { editor.delete(key.id) }
            }
            .help(ActionCatalog.descriptor(key.actionID).title)
    }
}

/// Renders a key or a live widget; shared with the device renderer.
struct WidgetOrKeyView: View {
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var store: ProfileStore
    let key: KeyAssignment

    var body: some View {
        if key.actionID.hasPrefix("pkg:") {
            PackageKeyFace(key: key)
        } else {
        switch key.actionID {
        case ActionID.mixerDashboard:
            // "Sync" (default) follows the mix the knobs control; otherwise the fixed mix chosen in the settings.
            MixerDashboardFace(mixer: store.mixer, bus: key.settings.bool("sync", true) ? store.mixer.activeMix : (MixBus(rawValue: key.settings.int("mix")) ?? .creator),
                               inputIndicator: key.settings.bool("input", true),
                               knobColors: (0..<6).map { store.library.device.ledKnob.knobColor($0) })
        case ActionID.pageIndicator:
            PageIndicatorFace(page: deck.currentPage, count: store.hotkey.pageCount, inFolder: deck.isInFolder)
        default:
            KeyFaceView(state: deck.state(for: key), style: key.style, overlayText: deck.liveText[key.id])
        }
        }
    }
}

struct PageIndicatorFace: View {
    let page: Int, count: Int, inFolder: Bool
    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            ZStack {
                Color(hex: "#18181C")
                VStack(spacing: h * 0.08) {
                    Text(inFolder ? "Cartella" : "\(page + 1)/\(count)").font(.system(size: h * 0.24, weight: .bold)).foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                    if !inFolder {
                        HStack(spacing: h * 0.05) {
                            ForEach(0..<count, id: \.self) { i in
                                Circle().fill(i == page ? Color.white : Color.gray.opacity(0.5)).frame(width: h * 0.07, height: h * 0.07)
                            }
                        }
                    }
                }
                .frame(width: g.size.width, height: h)
            }
        }
    }
}

struct MixerDashboardFace: View {
    let mixer: MixerProfile
    let bus: MixBus
    var inputIndicator = true
    /// Ring colours of the six knobs (same as the device LEDs).
    var knobColors: [Color] = Array(repeating: Color(hex: "#0A84FF"), count: 6)
    @ObservedObject private var meters = LevelMeters.shared

    var body: some View {
        GeometryReader { g in
            let u = g.size.width / 800 // panel units (the dashboard is 800 wide on the panel)
            let mix = mixer.mixes[mixer.dualMix ? bus : .creator] ?? MixState()
            HStack(spacing: 14 * u) {
                // Left: the mix the knobs drive.
                VStack(spacing: 18 * u) {
                    if mixer.dualMix {
                        busTile("CREATOR", "person.wave.2.fill", active: bus == .creator, u: u)
                        busTile("AUDIENCE", "dot.radiowaves.left.and.right", active: bus == .audience, u: u)
                    } else {
                        busTile("MASTER", "slider.vertical.3", active: true, u: u)
                    }
                }
                .frame(width: 190 * u)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 18 * u).fill(Color(hex: "#5B8CFF").opacity(0.08)))
                // Right: six channels, drawn like the knobs of the device.
                VStack(spacing: 16 * u) {
                    HStack(spacing: 0) { ForEach(MixerChannel.allCases.prefix(3)) { ch in channel(ch, mix, u) } }
                    HStack(spacing: 0) { ForEach(MixerChannel.allCases.suffix(3)) { ch in channel(ch, mix, u) } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(14 * u)
            // Midnight blue background.
            .background(LinearGradient(colors: [Color(hex: "#1B2A4A"), Color(hex: "#0B1426")], startPoint: .top, endPoint: .bottom))
        }
    }

    private func busTile(_ title: String, _ symbol: String, active: Bool, u: CGFloat) -> some View {
        let size: CGFloat = (mixer.dualMix ? 92 : 112) * u
        return VStack(spacing: 10 * u) {
            RoundedRectangle(cornerRadius: size * 0.27)
                .fill(active ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#FFB340"), Color(hex: "#FF7A00")], startPoint: .top, endPoint: .bottom))
                             : AnyShapeStyle(Color.white.opacity(0.08)))
                .frame(width: size, height: size)
                .overlay(Image(systemName: symbol).font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(active ? .white : Color.white.opacity(0.45)))
                .shadow(color: active ? Color(hex: "#FF7A00").opacity(0.45) : .clear, radius: 10 * u, y: 4 * u)
            Text(title).font(.system(size: 17 * u, weight: .semibold)).tracking(1.5 * u)
                .foregroundStyle(active ? .white : Color.white.opacity(0.45))
        }
    }

    private func channel(_ ch: MixerChannel, _ mix: MixState, _ u: CGFloat) -> some View {
        let s = mix.channels[ch] ?? ChannelState()
        let ring: Color = s.muted ? Color(hex: "#FF453A") : knobColors[MixerChannel.allCases.firstIndex(of: ch) ?? 0]
        return VStack(spacing: 10 * u) {
            ZStack {
                // Volume: 270° arc like the device knobs (red when muted).
                Circle().trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 8 * u, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: 0.75 * CGFloat(s.level) / 100)
                    .stroke(ring, style: StrokeStyle(lineWidth: 8 * u, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .shadow(color: ring.opacity(0.6), radius: 4 * u)
                // Live input level, inside the volume arc.
                if inputIndicator {
                    let lvl = CGFloat(meters.values[mixer.dualMix ? bus : .creator]?[ch] ?? 0) / 100
                    Circle().trim(from: 0, to: 0.75 * (s.muted ? 0 : lvl))
                        .stroke(Color(hex: "#30D158"), style: StrokeStyle(lineWidth: 3 * u, lineCap: .round))
                        .rotationEffect(.degrees(135)).padding(11 * u)
                }
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "#434347"), Color(hex: "#1D1D20")], center: .top, startRadius: 1, endRadius: 40 * u))
                    .padding(17 * u)
                    .shadow(color: .black.opacity(0.6), radius: 3 * u, y: 2 * u)
                Text("\(s.level)").font(.system(size: 24 * u, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(s.muted ? Color(hex: "#FF453A") : .white)
            }
            .frame(width: 92 * u, height: 92 * u)
            Text(mixer.name(ch).uppercased()).font(.system(size: 14 * u, weight: .semibold)).tracking(1.2 * u)
                .foregroundStyle(Color.white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pages

struct PageBar: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var editor: DeckEditorModel

    var body: some View {
        HStack(spacing: 8) {
            if deck.isInFolder {
                Button { deck.leaveFolder() } label: { Label("Esci dalla cartella", systemImage: "chevron.backward") }
            } else {
                Button { deck.previousPage() } label: { Image(systemName: "chevron.left") }
                ForEach(0..<store.hotkey.pageCount, id: \.self) { p in
                    Button { deck.go(toPage: p) } label: {
                        Text("\(p + 1)").frame(width: 22)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(p == deck.currentPage ? .accentColor : .gray.opacity(0.4))
                }
                Button { deck.nextPage() } label: { Image(systemName: "chevron.right") }
                Divider().frame(height: 18)
                Button { editor.addPage() } label: { Image(systemName: "plus") }.help("Aggiungi pagina")
                Button { editor.removeCurrentPage() } label: { Image(systemName: "minus") }.help("Rimuovi pagina corrente")
                    .disabled(store.hotkey.pageCount <= 1)
            }
            Spacer()
            Text("Trascina un'azione o un widget su uno slot libero del pannello.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
