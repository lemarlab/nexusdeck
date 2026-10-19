import SwiftUI

enum MainSection: String { case hotkeys, mixer, mic, apps }

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, audioOutput, obs, streamlabs, linkApps, customLighting, interactiveLighting, backup, guide, feedback
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .general: "Generale"
        case .audioOutput: "Uscita audio"
        case .obs: "OBS"
        case .streamlabs: "Streamlabs Desktop"
        case .linkApps: "Collega applicazioni"
        case .customLighting: "Illuminazione personalizzata"
        case .interactiveLighting: "Illuminazione interattiva"
        case .backup: "Backup e ripristino"
        case .guide: "Guida alle impostazioni"
        case .feedback: "Feedback"
        }
    }
}

enum MicEffectTab: String, CaseIterable, Identifiable {
    case noiseGate, compressor, equalizer, echo, reverb
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .noiseGate: "Noise Gate"
        case .compressor: "Compressore"
        case .equalizer: "Equalizzatore"
        case .echo: "Eco"
        case .reverb: "Riverbero"
        }
    }
}

/// UI navigation state shared by the shell.
@MainActor
final class UIState: ObservableObject {
    @Published var section: MainSection = .hotkeys
    @Published var sidebarExpanded = false
    @Published var settingsPage: SettingsPage?
    @Published var showStore = false
    @Published var showImport = false
    @Published var showRouting = false
    @Published var showMixerTools = false
    @Published var micTab: MicEffectTab = .noiseGate
    @Published var micEffectTab: MicEffectTab?
    /// Knob selected in the mixer view (0...5).
    @Published var mixerKnob: Int?
}

struct ShellView: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.titleLine).frame(height: 1)
            HeaderBar()
            HStack(spacing: 0) {
                Color.clear.frame(width: Theme.sidebarWidth)
                Group {
                    switch ui.section {
                    case .hotkeys: ActionListColumn()
                    case .mixer: MixerColumn()
                    case .mic: MicColumn()
                    case .apps: EmptyView()
                    }
                }
                .frame(width: ui.section == .apps ? 0 : Theme.columnWidth)
                .background(Theme.column)
                Group {
                    if ui.section == .apps {
                        AppRoutingPage()
                    } else if ui.section == .mic {
                        MicEffectsPanel()
                    } else {
                        VStack(spacing: 0) {
                            DeviceCanvas().frame(maxWidth: .infinity, maxHeight: .infinity)
                            PropertiesPanel().frame(height: Theme.propertiesHeight)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
            }
            .overlay(alignment: .leading) { Sidebar() }
        }
        .background(Theme.window)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .sheet(item: $ui.settingsPage) { _ in SettingsWindow() }
        .sheet(isPresented: $ui.showStore) { StoreWindow() }
        .sheet(isPresented: $ui.showImport) { ImportWindow() }
        .sheet(isPresented: $ui.showRouting) { RoutingTableWindow() }
        .sheet(isPresented: $ui.showMixerTools) { MixerToolsWindow() }
        .sheet(isPresented: Binding(get: { !store.library.tutorialDone }, set: { if !$0 { store.library.tutorialDone = true } })) { TutorialView() }
    }
}

// MARK: - Header

/// App mark drawn with our own artwork.
struct BrandMark: View {
    var size: CGFloat = 20
    var body: some View {
        HStack(spacing: size * 0.25) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22).fill(Theme.accent)
                Image(systemName: "square.grid.3x3.fill").font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(.black)
            }
            .frame(width: size, height: size)
            Text("NexusDeck").font(.system(size: size * 0.82, weight: .heavy)).italic().foregroundStyle(.white)
        }
    }
}

struct HeaderBar: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var editor: DeckEditorModel
    @EnvironmentObject var audio: AudioService
    @State private var dialog: ProfileDialog?
    @State private var message: String?

    enum ProfileDialog: Identifiable { case add, rename, delete; var id: Int { hashValue } }

    var body: some View {
        HStack(spacing: 0) {
            BrandMark().padding(.leading, 16)
            Spacer()
            if ui.section != .apps {
            Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textMid).padding(.trailing, 10)
            profilePicker.frame(width: 238)
            Menu {
                Button("Nuovo profilo…") { dialog = .add }
                Button("Duplica profilo") { duplicate() }
                Button("Rinomina profilo…") { dialog = .rename }
                Button("Elimina profilo…") { dialog = .delete }
                Divider()
                Button("Importa profilo…") { importProfile() }
                Button("Esporta profilo…") { exportProfile() }
                Divider()
                Button("Ripristina predefinito") { reset() }
            } label: {
                Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textDim)
                    .frame(width: 30, height: 30).background(Theme.field)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .padding(.leading, 6).padding(.trailing, 7)
            }
        }
        .frame(height: Theme.headerHeight)
        .background(Theme.topBar)
        .sheet(item: $dialog) { d in
            switch d {
            case .add: NameDialog(title: "Aggiungi nuovo profilo", initial: "") { add($0) }
            case .rename: NameDialog(title: "Rinomina profilo", initial: currentTitle) { rename($0) }
            case .delete: ConfirmDialog(title: "Elimina profilo", message: "Eliminare il profilo \"\(currentTitle)\"?") { delete() }
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} }
    }

    private var label: LocalizedStringKey {
        switch ui.section {
        case .hotkeys: "Profilo tasti :"
        case .mixer, .apps: "Profilo mixer :"
        case .mic: "Impostazioni microfono"
        }
    }

    @ViewBuilder private var profilePicker: some View {
        switch ui.section {
        case .hotkeys:
            DarkPicker(selection: Binding(get: { store.hotkey.id }, set: { editor.activate($0) }),
                       options: store.library.hotkeyProfiles.map { ($0.id, $0.title) }, height: 30)
        case .mixer, .apps:
            DarkPicker(selection: Binding(get: { store.mixer.id }, set: { store.library.activeMixerProfile = $0; audio.applyAll() }),
                       options: store.library.mixerProfiles.map { ($0.id, $0.title) }, height: 30)
        case .mic:
            DarkPicker(selection: Binding(get: { store.dsp.id }, set: { store.library.activeDSPProfile = $0; audio.applyDSP() }),
                       options: store.library.dspProfiles.map { ($0.id, $0.title) }, height: 30)
        }
    }

    private var currentTitle: String {
        switch ui.section {
        case .hotkeys: store.hotkey.title
        case .mixer, .apps: store.mixer.title
        case .mic: store.dsp.title
        }
    }

    private func add(_ name: String) {
        switch ui.section {
        case .hotkeys:
            var p = HotkeyProfile(title: name); p.pageCount = 5
            store.library.hotkeyProfiles.append(p); editor.activate(p.id)
        case .mixer, .apps:
            let p = MixerProfile(title: name)
            store.library.mixerProfiles.append(p); store.library.activeMixerProfile = p.id; audio.applyAll()
        case .mic:
            let p = DSPProfile(title: name)
            store.library.dspProfiles.append(p); store.library.activeDSPProfile = p.id; audio.applyDSP()
        }
    }

    private func duplicate() {
        switch ui.section {
        case .hotkeys: editor.duplicateProfile()
        case .mixer, .apps:
            var p = store.mixer; p.id = UUID(); p.title += " (copia)"
            store.library.mixerProfiles.append(p); store.library.activeMixerProfile = p.id
        case .mic:
            var p = store.dsp; p.id = UUID(); p.title += " (copia)"
            store.library.dspProfiles.append(p); store.library.activeDSPProfile = p.id
        }
    }

    private func rename(_ name: String) {
        switch ui.section {
        case .hotkeys: store.hotkey.title = name
        case .mixer, .apps: store.mixer.title = name
        case .mic: store.dsp.title = name
        }
    }

    private func delete() {
        switch ui.section {
        case .hotkeys: editor.deleteProfile()
        case .mixer, .apps:
            guard store.library.mixerProfiles.count > 1 else { return }
            let id = store.mixer.id
            store.library.mixerProfiles.removeAll { $0.id == id }
            store.library.activeMixerProfile = store.library.mixerProfiles[0].id; audio.applyAll()
        case .mic:
            guard store.library.dspProfiles.count > 1 else { return }
            let id = store.dsp.id
            store.library.dspProfiles.removeAll { $0.id == id }
            store.library.activeDSPProfile = store.library.dspProfiles[0].id; audio.applyDSP()
        }
    }

    private func reset() {
        switch ui.section {
        case .hotkeys:
            let id = store.hotkey.id, t = store.hotkey.title
            var p = HotkeyProfile.makeDefault(); p.id = id; p.title = t
            store.hotkey = p; editor.activate(id)
        case .mixer, .apps:
            let id = store.mixer.id, t = store.mixer.title
            var p = MixerProfile(title: t); p.id = id
            store.mixer = p; audio.applyAll()
        case .mic:
            let id = store.dsp.id, t = store.dsp.title
            var p = DSPProfile(title: t); p.id = id
            store.dsp = p; audio.applyDSP()
        }
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.nexusProfile]
        panel.nameFieldStringValue = currentTitle
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch ui.section {
            case .hotkeys: try store.exportHotkeyProfile(store.hotkey, to: url)
            case .mixer, .apps: try JSONEncoder().encode(ProfileStore.ExportBundle(mixer: store.mixer)).write(to: url)
            case .mic: try JSONEncoder().encode(ProfileStore.ExportBundle(dsp: store.dsp)).write(to: url)
            }
        } catch { message = error.localizedDescription }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.nexusProfile, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.importProfile(from: url) } catch { message = "File non valido" }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            item("line.3.horizontal", nil, active: false, menu: true) { withAnimation(.easeOut(duration: 0.15)) { ui.sidebarExpanded.toggle() } }
                .padding(.bottom, 8)
            item("square.3.layers.3d", "Tasti e widget", active: ui.section == .hotkeys) { select(.hotkeys) }
            item("circle.hexagongrid.circle", "Mixer audio", active: ui.section == .mixer) { select(.mixer) }
            item("mic", "Impostazioni microfono", active: ui.section == .mic) { select(.mic) }
            item("app.connected.to.app.below.fill", "Instradamento app", active: ui.section == .apps) { select(.apps) }
            Spacer()
            item("puzzlepiece.extension", "Widget Store", active: false) { ui.showStore = true; ui.sidebarExpanded = false }
            item("rectangle.portrait.and.arrow.forward", "Importa widget", active: false) { ui.showImport = true; ui.sidebarExpanded = false }
            item("gearshape.fill", "Impostazioni", active: false) { ui.settingsPage = .general; ui.sidebarExpanded = false }
                .padding(.bottom, 6)
        }
        .padding(.top, 6)
        .frame(width: ui.sidebarExpanded ? Theme.sidebarExpandedWidth : Theme.sidebarWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
        .clipped()
    }

    private func select(_ s: MainSection) {
        ui.section = s
        ui.sidebarExpanded = false
    }

    private func item(_ symbol: String, _ title: LocalizedStringKey?, active: Bool, menu: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: menu ? 18 : 17, weight: menu ? .regular : .light))
                    .foregroundStyle(active || (menu && ui.sidebarExpanded) ? Theme.accent : Theme.textDim)
                    .frame(width: Theme.sidebarWidth, height: 38)
                if ui.sidebarExpanded, let title {
                    Text(title).font(.system(size: 13)).foregroundStyle(Theme.textMid)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active && !ui.sidebarExpanded ? Color(hex: "#454545") : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dialogs

struct NameDialog: View {
    let title: LocalizedStringKey
    let initial: String
    let onOK: (String) -> Void
    @State private var name = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 13, weight: .bold)).padding(16)
            VStack(alignment: .leading, spacing: 8) {
                Text("Nome profilo").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
                TextField("", text: $name).darkField().frame(width: 300).onSubmit(ok)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
            HStack {
                Spacer()
                FlatButton(title: "OK", width: 110, action: ok).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                FlatButton(title: "Annulla", width: 110) { dismiss() }
            }
            .padding(12)
        }
        .frame(width: 420)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .onAppear { name = initial }
    }

    private func ok() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        onOK(n); dismiss()
    }
}

struct ConfirmDialog: View {
    let title: LocalizedStringKey
    let message: String
    let onOK: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 13, weight: .bold))
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.textMid).frame(width: 360, alignment: .leading)
            HStack {
                Spacer()
                FlatButton(title: "OK", width: 110) { onOK(); dismiss() }
                FlatButton(title: "Annulla", width: 110) { dismiss() }
            }
        }
        .padding(16)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }
}

/// Modal window: title row, content, footer with "Chiudi".
struct ModalFrame<Content: View>: View {
    let title: LocalizedStringKey
    var width: CGFloat = 888
    var height: CGFloat = 760
    @ViewBuilder var content: Content
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textMid)
                Spacer()
            }
            .padding(.horizontal, 26).frame(height: 54)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack { Spacer(); FlatButton(title: "Chiudi", width: 118) { dismiss() } }
                .padding(.horizontal, 16).frame(height: 64)
                .background(Theme.settingsFooter)
        }
        .frame(width: width, height: height)
        .background(Theme.settingsBg)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }
}
