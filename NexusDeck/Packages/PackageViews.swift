import SwiftUI
import WebKit

// MARK: - Display of package widgets

/// Face of a key/widget provided by an SDK package, honoring live overrides from the package.
struct PackageKeyFace: View {
    let key: KeyAssignment
    @EnvironmentObject var deck: DeckController
    @ObservedObject private var sdk = SDKHost.shared

    var body: some View {
        let i = deck.stateIndex[key.id] ?? 0
        let state = key.states.indices.contains(i) ? key.states[i] : (key.states.first ?? KeyState())
        var shown = state
        if let t = sdk.titles[key.id]?[i] { shown.title = t }
        return ZStack {
            if let img = sdk.icons[key.id]?[i] {
                ZStack {
                    Color(hex: state.background)
                    Image(nsImage: img).resizable().scaledToFit()
                }
                .overlay(alignment: .bottom) { title(shown.title) }
            } else {
                KeyFaceView(state: shown, style: key.style)
            }
            if let overlay = sdk.overlays[key.id] {
                Image(nsImage: overlay).resizable().scaledToFill()
            }
            switch sdk.effects[key.id] {
            case "press": Rectangle().strokeBorder(Color(hex: "#FF9900"), lineWidth: 4)
            case "invalid":
                Color.black.opacity(0.55)
                Image(systemName: "nosign").font(.system(size: 22, weight: .bold)).foregroundStyle(.white.opacity(0.8))
            default: EmptyView()
            }
        }
        .clipped()
    }

    @ViewBuilder private func title(_ t: String) -> some View {
        if !t.isEmpty {
            Text(t).font(.system(size: key.style.size, weight: key.style.bold ? .bold : .regular))
                .foregroundStyle(Color(hex: key.style.colorHex)).lineLimit(2).padding(4)
        }
    }
}

// MARK: - Property view

/// Hosts a package's HTML property view and connects it to the SDK server.
struct PackagePropertyView: NSViewRepresentable {
    let key: KeyAssignment
    let url: URL
    let root: URL

    func makeCoordinator() -> Coordinator { Coordinator(key: key) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        web.uiDelegate = context.coordinator
        web.loadFileURL(url, allowingReadAccessTo: root)
        SDKHost.shared.propertyViewAppeared(key)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        let key = coordinator.key
        Task { @MainActor in SDKHost.shared.propertyViewDisappeared(key) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let key: KeyAssignment
        init(key: KeyAssignment) { self.key = key }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let key = self.key
            Task { @MainActor in
                _ = try? await webView.evaluateJavaScript(SDKHost.shared.propertyViewConnectScript(key))
            }
        }

        // Links that open new windows go to the browser.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = navigationAction.request.url { NSWorkspace.shared.open(u) }
            return nil
        }
    }
}

// MARK: - Widget Store

struct StoreWindow: View {
    enum Page: CaseIterable { case all, mine, hotkeys, micPresets }
    @State private var page: Page = .all
    @State private var search = ""
    @ObservedObject private var pm = PackageManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.separator).frame(width: 0.5)
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(page)).font(.system(size: 22, weight: .bold))
                        Text(subtitle(page)).font(.system(size: 12.5)).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                }
                .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 14)
                ScrollView {
                    switch page {
                    case .all, .mine: packageGrid
                    case .hotkeys, .micPresets:
                        VStack(spacing: 10) {
                            Image(systemName: page == .hotkeys ? "square.grid.3x3" : "slider.vertical.3").font(.system(size: 34)).foregroundStyle(Theme.textFaint)
                            Text("Importa profili e preset da file").font(.system(size: 14, weight: .semibold))
                            Text("Usa «Importa» nella barra laterale di NexusDeck oppure «Installa da file…» qui a sinistra.")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 90)
                    }
                }
                    HStack { Spacer(); FlatButton(title: "Fine", prominent: true, width: 90) { dismiss() } }
                        .padding(.horizontal, 20).frame(height: 56)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 0.5) }

            }
            .frame(maxWidth: .infinity)
            .background(Theme.canvas)
        }
        .frame(width: 900, height: 640)
        .alert(pm.lastError ?? "", isPresented: Binding(get: { pm.lastError != nil }, set: { if !$0 { pm.lastError = nil } })) { Button("OK") {} }
    }

    private func title(_ p: Page) -> LocalizedStringKey {
        switch p { case .all: "Scopri"; case .mine: "Installati"; case .hotkeys: "Profili tasti"; case .micPresets: "Preset microfono" }
    }
    private func subtitle(_ p: Page) -> LocalizedStringKey {
        switch p {
        case .all: "Integrazioni incluse e widget installati"
        case .mine: "I widget installati su questo Mac"
        case .hotkeys: "Profili di tasti e widget condivisi"
        case .micPresets: "Impostazioni del microfono condivise"
        }
    }
    private func symbol(_ p: Page) -> (String, String) {
        switch p {
        case .all: ("sparkles", "#0A84FF")
        case .mine: ("square.and.arrow.down.fill", "#34C759")
        case .hotkeys: ("square.grid.3x3.fill", "#FF7A00")
        case .micPresets: ("slider.vertical.3", "#BF5AF2")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                TextField("Cerca", text: $search).textFieldStyle(.plain).font(.system(size: 12.5))
            }
            .padding(.horizontal, 9).frame(height: 28)
            .background(Theme.field).clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(.top, 20).padding(.bottom, 12)
            ForEach(Page.allCases, id: \.self) { p in
                let on = page == p
                Button { page = p } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 6).fill(Color(hex: symbol(p).1)).frame(width: 24, height: 24)
                            .overlay(Image(systemName: symbol(p).0).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
                        Text(title(p)).font(.system(size: 13, weight: on ? .medium : .regular)).foregroundStyle(on ? Color.white : Theme.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).frame(height: 34)
                    .background(on ? Theme.accent : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { installFromFile() } label: {
                Label("Installa da file…", systemImage: "square.and.arrow.down").font(.system(size: 12.5))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent).padding(.bottom, 18).padding(.leading, 6)
        }
        .padding(.horizontal, 12)
        .frame(width: 210)
        .background(VisualEffect(material: .sidebar))
    }

    private var packageGrid: some View {
        let installedIDs = Set(pm.packages.map(\.uuid))
        let list: [StoreItem] = page == .mine
            ? pm.packages.map { StoreItem(installed: $0, catalog: nil) }
            : PackageManager.catalog.map { c in StoreItem(installed: pm.packages.first { $0.uuid == c.id }, catalog: c) }
                + pm.packages.filter { p in !PackageManager.catalog.contains { $0.id == p.uuid } }.map { StoreItem(installed: $0, catalog: nil) }
        let filtered = list.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        let integrations = page == .all ? BuiltInIntegration.allCases.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } : []
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return VStack(alignment: .leading, spacing: 12) {
            if !integrations.isEmpty {
                sectionTitle("Integrazioni incluse")
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(integrations) { IntegrationCard(integration: $0) }
                }
            }
            if !filtered.isEmpty {
                sectionTitle("Widget installati").padding(.top, integrations.isEmpty ? 0 : 12)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filtered) { item in StoreCard(item: item, installed: item.installed != nil || installedIDs.contains(item.id)) }
                }
            } else if page == .mine {
                Text("Nessun widget installato. Usa «Installa da file…» per aggiungerne uno.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textDim).padding(.top, 30)
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 24)
    }

    private func sectionTitle(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.system(size: 15, weight: .bold))
    }

    private func installFromFile() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        for u in p.urls { Task { await pm.install(from: u) } }
    }
}

/// App Store–style capsule button ("Attiva", "Installa").
struct CapsuleButton: View {
    let title: LocalizedStringKey
    var filled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .bold))
                .foregroundStyle(filled ? Color.white : Theme.accent)
                .padding(.horizontal, 16).frame(height: 26)
                .background(filled ? Theme.accent : Theme.accent.opacity(0.14))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct StoreItem: Identifiable {
    let installed: InstalledPackage?
    let catalog: CatalogPackage?
    var id: String { installed?.uuid ?? catalog?.id ?? UUID().uuidString }
    var name: String { installed?.name ?? catalog?.name ?? "" }
    /// The vendor name is not shown in NexusDeck's store.
    var author: String {
        let a = installed?.author ?? catalog?.author ?? ""
        return a.localizedCaseInsensitiveContains("avermedia") ? "" : a
    }
    var summary: String { catalog?.summary ?? installed?.description ?? "" }
}

private struct StoreCard: View {
    let item: StoreItem
    let installed: Bool
    @ObservedObject private var pm = PackageManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            icon.frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 13))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.system(size: 14, weight: .semibold))
                Text([item.author, item.installed.map { "v\($0.version)" } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                if let p = item.installed, !p.runsNatively {
                    Text("Solo Intel – non compatibile").font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                        .help("Questo pacchetto contiene solo codice Intel: richiede Rosetta, che macOS 28 non supporta più. NexusDeck non lo avvia.")
                }
                Text(item.summary).font(.system(size: 12)).foregroundStyle(Theme.textMid).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if pm.installing.contains(item.catalog?.url.absoluteString ?? "-") {
                ProgressView().controlSize(.small)
            } else if installed {
                CapsuleButton(title: "Rimuovi", filled: false) { pm.uninstall(item.id) }
            } else if let c = item.catalog {
                CapsuleButton(title: "Installa") { Task { await pm.install(from: c.url) } }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    @ViewBuilder private var icon: some View {
        if let p = item.installed, let img = NSImage(contentsOf: p.file(p.icon)) {
            Image(nsImage: img).resizable().scaledToFit().background(Theme.field)
        } else if let u = item.catalog?.iconURL {
            AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Theme.field }
        } else {
            ZStack { Theme.field; Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 24)).foregroundStyle(Theme.textDim) }
        }
    }
}

/// An integration built into NexusDeck: nothing to download, just switch it on or off.
private struct IntegrationCard: View {
    let integration: BuiltInIntegration
    @EnvironmentObject var engine: ActionEngine
    @AppStorage private var enabled: Bool

    init(integration: BuiltInIntegration) {
        self.integration = integration
        _enabled = AppStorage(wrappedValue: false, integration.defaultsKey)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 13)
                .fill(LinearGradient(colors: [Color(hex: Theme.lighten(integration.color, 0.15)), Color(hex: integration.color)], startPoint: .top, endPoint: .bottom))
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: integration.symbol).font(.system(size: 24)).foregroundStyle(.white))
                .shadow(color: Color(hex: integration.color).opacity(0.35), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(integration.title).font(.system(size: 14, weight: .semibold))
                HStack(spacing: 4) {
                    Circle().fill(enabled ? Color.green : Theme.textFaint).frame(width: 6, height: 6)
                    Text(enabled ? "Attiva" : "Inclusa").font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                }
                .fixedSize()
                Text(integration.summary).font(.system(size: 12)).foregroundStyle(Theme.textMid).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CapsuleButton(title: enabled ? "Disattiva" : "Attiva", filled: !enabled) {
                enabled.toggle()
                engine.applyBuiltInIntegrations()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}
