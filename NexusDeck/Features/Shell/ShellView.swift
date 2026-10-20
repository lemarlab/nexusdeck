import SwiftUI

extension Notification.Name {
    static let nexusRetryMixer = Notification.Name("NexusDeck.retryMixer")
}

enum MainSection: String, CaseIterable {
    case hotkeys, mixer, mic, apps, matrix, ducking, obs, lighting, integrations

    enum ProfileKind { case hotkeys, mixer, mic }
    /// Which profile the header picker edits.
    var profileKind: ProfileKind {
        switch self {
        case .hotkeys: .hotkeys
        case .mic: .mic
        default: .mixer
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .hotkeys: "Widget"
        case .mixer: "Mixer"
        case .mic: "Microfono"
        case .apps: "Instradamento app"
        case .matrix: "Matrice audio"
        case .ducking: "Voce in primo piano"
        case .obs: "Tracce per lo streaming"
        case .lighting: "Illuminazione"
        case .integrations: "Integrazioni"
        }
    }
    var tint: Color {
        switch self {
        case .hotkeys: Color(hex: "#FF7A00")
        case .mixer: Color(hex: "#FF2D55")
        case .mic: Color(hex: "#FF9500")
        case .apps: Color(hex: "#0A84FF")
        case .matrix: Color(hex: "#5E5CE6")
        case .ducking: Color(hex: "#30B0C7")
        case .obs: Color(hex: "#FF3B30")
        case .lighting: Color(hex: "#FF9F0A")
        case .integrations: Color(hex: "#0A84FF")
        }
    }
    var symbol: String {
        switch self {
        case .hotkeys: "square.grid.3x3.fill"
        case .mixer: "slider.vertical.3"
        case .mic: "mic.fill"
        case .apps: "arrow.triangle.branch"
        case .matrix: "point.3.connected.trianglepath.dotted"
        case .ducking: "arrow.down.right.and.arrow.up.left"
        case .obs: "record.circle"
        case .lighting: "lightbulb.fill"
        case .integrations: "link"
        }
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, audioOutput, backup, guide, feedback
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .audioOutput: "speaker.wave.2.fill"
        case .backup: "externaldrive.fill"
        case .guide: "book.fill"
        case .feedback: "bubble.left.fill"
        }
    }
    var tint: Color {
        switch self {
        case .general: Color(hex: "#8E8E93")
        case .audioOutput: Color(hex: "#FF2D55")
        case .backup: Color(hex: "#30B0C7")
        case .guide: Color(hex: "#FF7A00")
        case .feedback: Color(hex: "#34C759")
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .general: "Generale"
        case .audioOutput: "Uscita audio"
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
    /// While the mixer is being set up at launch the window is blurred.
    @Published var loading = true
    /// Mixer link shown over the window: connecting (start), reconnecting (cable unplugged), not found (error).
    enum Link: Equatable { case connecting, reconnecting, notFound }
    @Published var link: Link = .connecting
    /// The user chose to keep working without the mixer.
    @Published var dismissedNotFound = false
    /// Quitting: the loading overlay says the mixer is being disconnected.
    @Published var closing = false
    @Published var micTab: MicEffectTab = .noiseGate
    @Published var micEffectTab: MicEffectTab?
    /// Knob selected in the mixer view (0...5).
    @Published var mixerKnob: Int?
}

struct ShellView: View {
    @EnvironmentObject var ui: UIState
    @ObservedObject private var updater = Updater.shared
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        HStack(spacing: 0) {
            Sidebar().frame(width: 220)
            Rectangle().fill(Theme.separator).frame(width: 0.5)
            VStack(spacing: 0) {
                HeaderBar()
                Rectangle().fill(Theme.separator).frame(height: 0.5)
                sectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background(Theme.canvas)
            }
        }
        .blur(radius: ui.loading ? 22 : 0)
        // Nothing behind the overlay can be used while it is shown.
        .allowsHitTesting(!ui.loading)
        .overlay {
            if ui.loading {
                ZStack {
                    // Catches every click and drag outside the message.
                    Color.black.opacity(0.001).contentShape(Rectangle())
                        .onTapGesture {}
                        .gesture(DragGesture(minimumDistance: 0))
                // One card for every state: its content changes, the card stays.
                MixerLinkCard(link: ui.closing ? nil : ui.link, retry: {
                    ui.link = .connecting; NotificationCenter.default.post(name: .nexusRetryMixer, object: nil)
                }, offline: {
                    ui.dismissedNotFound = true; ui.loading = false
                })
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: ui.link)
        .animation(.easeOut(duration: 0.5), value: ui.loading)
        .ignoresSafeArea()
        .background(Theme.window)
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        // Open windows (settings, store…) close when the mixer link is lost.
        .onChange(of: ui.loading) { _, blocked in
            if blocked && !ui.closing { ui.settingsPage = nil; updater.showSheet = false }
        }
        .sheet(item: $ui.settingsPage) { _ in SettingsWindow() }
        .sheet(isPresented: $updater.showSheet) { UpdateSheet() }
        .sheet(isPresented: Binding(get: { !store.library.tutorialDone }, set: { if !$0 { store.library.tutorialDone = true } })) { TutorialView() }
    }

    @ViewBuilder private var sectionContent: some View {
        switch ui.section {
        case .hotkeys, .mixer:
            HStack(spacing: 0) {
                if ui.section == .hotkeys {
                    ActionListColumn().frame(width: 260).background(Theme.column)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Rectangle().fill(Theme.separator).frame(width: 0.5)
                }
                DeckStage().frame(minWidth: 830, maxWidth: .infinity, maxHeight: .infinity).layoutPriority(1)
            }
        case .mic:
            MicPage()
        case .apps: AppRoutingPage()
        case .matrix: PageScroll { RoutingMatrix() }
        case .ducking: PageScroll { DuckingPage() }
        case .obs: PageScroll { OBSTracksPage() }
        case .lighting: LightingPage()
        case .integrations: PageScroll { IntegrationsPage() }
        }
    }
}

/// The mixer link message: connecting / reconnecting / disconnecting (spinner) or not found (warning, Retry).
struct MixerLinkCard: View {
    /// nil = quitting.
    let link: UIState.Link?
    let retry: () -> Void
    let offline: () -> Void

    var body: some View {
        let failed = link == .notFound
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96).opacity(failed ? 0.55 : 1)
                if failed {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30))
                        .symbolRenderingMode(.palette).foregroundStyle(.white, .orange)
                        .shadow(color: .black.opacity(0.3), radius: 3).offset(x: 6, y: 6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(title).font(.system(size: 17, weight: .bold))
            if failed {
                Text("Collega l'AX310 al Mac con il cavo USB: NexusDeck si ricollegherà da solo.\nPuoi anche preparare tasti e profili senza mixer.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    FlatButton(title: "Utilizza senza mixer", width: 170, action: offline)
                    FlatButton(title: "Riprova", prominent: true, width: 110, action: retry)
                }
                .padding(.top, 4)
            } else {
                ProgressView().controlSize(.small).padding(.top, 2)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
            }
        }
        .frame(width: 380)
        .padding(.vertical, 28)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .animation(.easeOut(duration: 0.25), value: link)
    }

    private var title: LocalizedStringKey {
        switch link {
        case nil: "Scollegamento dal mixer…"
        case .connecting: "Collegamento al mixer…"
        case .reconnecting: "Riconnessione in corso…"
        case .notFound: "Mixer non trovato"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch link {
        case nil: "Spegnimento delle luci e del display."
        case .connecting: "Invio della configurazione al mixer."
        case .reconnecting: "Il cavo USB è stato scollegato: in attesa del mixer."
        case .notFound: ""
        }
    }
}

/// Scrollable page body with standard margins.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            content.padding(28).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
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
                Image(systemName: "square.grid.3x3.fill").font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            Text("NexusDeck").font(.system(size: size * 0.82, weight: .heavy)).italic().foregroundStyle(Theme.text)
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
            Text(ui.section.title).font(.system(size: 15, weight: .bold)).padding(.leading, 20)
            if ui.section == .mixer && store.mixer.dualMix {
                MixSegment().padding(.leading, 18)
            }
            UpdateBadge().padding(.leading, 14)
            Spacer()
            if ![.apps, .lighting, .integrations].contains(ui.section) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.textDim).padding(.trailing, 8)
            profilePicker.frame(width: 220)
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
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16)).foregroundStyle(Theme.textDim)
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .padding(.leading, 6).padding(.trailing, 14)
            }
        }
        .frame(height: 52)
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
        switch ui.section.profileKind {
        case .hotkeys: "Profilo tasti"
        case .mixer: "Profilo mixer"
        case .mic: "Profilo voce"
        }
    }

    @ViewBuilder private var profilePicker: some View {
        switch ui.section.profileKind {
        case .hotkeys:
            DarkPicker(selection: Binding(get: { store.hotkey.id }, set: { editor.activate($0) }),
                       options: store.library.hotkeyProfiles.map { ($0.id, $0.title) }, height: 30)
        case .mixer:
            DarkPicker(selection: Binding(get: { store.mixer.id }, set: { store.library.activeMixerProfile = $0; audio.applyAll() }),
                       options: store.library.mixerProfiles.map { ($0.id, $0.title) }, height: 30)
        case .mic:
            DarkPicker(selection: Binding(get: { store.dsp.id }, set: { store.library.activeDSPProfile = $0; audio.applyDSP() }),
                       options: store.library.dspProfiles.map { ($0.id, $0.title) }, height: 30)
        }
    }

    private var currentTitle: String {
        switch ui.section.profileKind {
        case .hotkeys: store.hotkey.title
        case .mixer: store.mixer.title
        case .mic: store.dsp.title
        }
    }

    private func add(_ name: String) {
        switch ui.section.profileKind {
        case .hotkeys:
            var p = HotkeyProfile(title: name); p.pageCount = 5
            store.library.hotkeyProfiles.append(p); editor.activate(p.id)
        case .mixer:
            let p = MixerProfile(title: name)
            store.library.mixerProfiles.append(p); store.library.activeMixerProfile = p.id; audio.applyAll()
        case .mic:
            let p = DSPProfile(title: name)
            store.library.dspProfiles.append(p); store.library.activeDSPProfile = p.id; audio.applyDSP()
        }
    }

    private func duplicate() {
        switch ui.section.profileKind {
        case .hotkeys: editor.duplicateProfile()
        case .mixer:
            var p = store.mixer; p.id = UUID(); p.title += " (copia)"
            store.library.mixerProfiles.append(p); store.library.activeMixerProfile = p.id
        case .mic:
            var p = store.dsp; p.id = UUID(); p.title += " (copia)"
            store.library.dspProfiles.append(p); store.library.activeDSPProfile = p.id
        }
    }

    private func rename(_ name: String) {
        switch ui.section.profileKind {
        case .hotkeys: store.hotkey.title = name
        case .mixer: store.mixer.title = name
        case .mic: store.dsp.title = name
        }
    }

    private func delete() {
        switch ui.section.profileKind {
        case .hotkeys: editor.deleteProfile()
        case .mixer:
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
        switch ui.section.profileKind {
        case .hotkeys:
            let id = store.hotkey.id, t = store.hotkey.title
            var p = HotkeyProfile.makeDefault(); p.id = id; p.title = t
            store.hotkey = p; editor.activate(id)
        case .mixer:
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
            switch ui.section.profileKind {
            case .hotkeys: try store.exportHotkeyProfile(store.hotkey, to: url)
            case .mixer: try JSONEncoder().encode(ProfileStore.ExportBundle(mixer: store.mixer)).write(to: url)
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

/// Shown in the header when a new version is available: opens Settings → General.
private struct UpdateBadge: View {
    @ObservedObject var updater = Updater.shared
    @EnvironmentObject var ui: UIState

    var body: some View {
        if let v = updater.latestVersion {
            Button { updater.showSheet = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 11, weight: .semibold))
                    Text("Aggiornamento \(v)").font(.system(size: 11.5, weight: .bold))
                }
                .foregroundStyle(.black).padding(.horizontal, 9).frame(height: 22)
                .background(Theme.accent).clipShape(Capsule())
            }
            .buttonStyle(.plain).help("È disponibile una nuova versione di NexusDeck")
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var devices: DeviceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Color.clear.frame(height: 44) // traffic lights
            group("Dispositivo")
            item(.hotkeys); item(.mixer); item(.mic)
            group("Audio")
            item(.apps); item(.matrix); item(.ducking); item(.obs)
            group("Altro")
            item(.lighting); item(.integrations)
            Spacer()
            deviceCard
            row("gearshape.fill", "Impostazioni", tint: "#8E8E93") { ui.settingsPage = .general }
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffect(material: .sidebar).ignoresSafeArea())
    }

    private func group(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textFaint)
            .padding(.leading, 10).padding(.top, 14).padding(.bottom, 4)
    }

    private func item(_ s: MainSection) -> some View {
        let on = ui.section == s
        return Button { withAnimation(.spring(response: 0.6, dampingFraction: 0.88)) { ui.section = s } } label: {
            HStack(spacing: 9) {
                SidebarIcon(symbol: s.symbol, tint: s.tint)
                Text(s == .obs ? "Tracce streaming" : s.title).font(.system(size: 13, weight: on ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(on ? Theme.selection : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ symbol: String, _ t: LocalizedStringKey, tint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SidebarIcon(symbol: symbol, tint: Color(hex: tint))
                Text(t).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var deviceCard: some View {
        let connected: (String, String)? = {
            if case .connected(let i) = devices.state { return (i.productName, i.firmwareVersion) }
            return nil
        }()
        return HStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [Color(hex: "#3A3A3E"), Color(hex: "#1B1B1D")], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: "#4A6CFF").opacity(0.85)).frame(width: 18, height: 12).padding(5)
            }
            .frame(width: 40, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(connected != nil ? "AX310" : "Nessun mixer").font(.system(size: 12.5, weight: .semibold))
                HStack(spacing: 4) {
                    Circle().fill(connected != nil ? Color.green : Color.gray).frame(width: 7, height: 7)
                    Text(connected != nil ? "Collegato" : "Non collegato")
                        .font(.system(size: 11)).foregroundStyle(Theme.textDim).lineLimit(1)
                }
                if let fw = connected?.1, !fw.isEmpty {
                    Text("Firmware \(fw)").font(.system(size: 10.5)).foregroundStyle(Theme.textFaint).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 6)
    }
}

/// Small coloured rounded square with a white symbol (System Settings style).
struct SidebarIcon: View {
    let symbol: String
    let tint: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom))
            .frame(width: 22, height: 22)
            .overlay(Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
    }
}

/// AppKit translucent material (sidebar, popovers).
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Creator | Audience switch shown in the toolbar with Dual Mix.
struct MixSegment: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var engine: ActionEngine

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MixBus.allCases) { b in
                let on = store.mixer.activeMix == b
                Button {
                    if !on { audio.switchActiveMix(); engine.syncStates() }
                } label: {
                    Text(b == .creator ? "Creator" : "Audience").font(.system(size: 12, weight: on ? .medium : .regular))
                        .foregroundStyle(on ? Theme.text : Theme.textDim)
                        .padding(.horizontal, 14).frame(height: 22)
                        .background(on ? Theme.card : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 0.5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 7))
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
            HStack { Spacer(); FlatButton(title: "Fine", prominent: true, width: 90) { dismiss() } }
                .padding(.horizontal, 16).frame(height: 64)
                .background(Theme.settingsFooter)
        }
        .frame(width: width, height: height)
        .background(Theme.settingsBg)
        .foregroundStyle(Theme.text)
        
    }
}
