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
    enum Page { case all, mine, hotkeys, micPresets }
    @State private var page: Page = .all
    @State private var search = ""
    @ObservedObject private var pm = PackageManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "cart.fill").font(.system(size: 20))
                Text("Widget Store").font(.system(size: 16))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(Color(hex: "#2D2D2D"))
            HStack(spacing: 0) {
                sidebar
                content
            }
        }
        .frame(width: 888, height: 760)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .alert(pm.lastError ?? "", isPresented: Binding(get: { pm.lastError != nil }, set: { if !$0 { pm.lastError = nil } })) { Button("OK") {} }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) { Image(systemName: "square.grid.2x2"); Text("Pacchetti") }
                .font(.system(size: 15)).padding(.leading, 24).frame(height: 50)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#363636"))
                .overlay(alignment: .leading) { Rectangle().fill(Color(hex: "#E4002B")).frame(width: 3).padding(.vertical, 8).padding(.leading, 10) }
            item("Tutti i pacchetti", .all, indent: true)
            item("I miei pacchetti", .mine, indent: true)
            item("Profili tasti", .hotkeys, symbol: "slider.horizontal.below.rectangle")
            item("Preset microfono", .micPresets, symbol: "slider.vertical.3")
            Spacer()
            Button { installFromFile() } label: { Label("Installa da file…", systemImage: "square.and.arrow.down") }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.textMid).padding(20)
        }
        .frame(width: 180)
        .background(Color(hex: "#2B2B2B"))
    }

    private func item(_ t: LocalizedStringKey, _ p: Page, indent: Bool = false, symbol: String? = nil) -> some View {
        Button { page = p } label: {
            HStack(spacing: 12) {
                if let symbol { Image(systemName: symbol) }
                Text(t)
            }
            .font(.system(size: 15))
            .foregroundStyle(page == p ? Color(hex: "#E4002B") : Theme.textMid)
            .padding(.leading, indent ? 50 : 24).frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 16)).foregroundStyle(Theme.textDim).padding(.trailing, 16)
                HStack {
                    TextField("Cerca", text: $search).textFieldStyle(.plain).font(.system(size: 14))
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textDim)
                }
                .padding(.horizontal, 12).frame(width: 256, height: 36).background(Color(hex: "#232323")).clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.trailing, 50).padding(.top, 20).padding(.bottom, 16)
            ScrollView {
                switch page {
                case .all, .mine: packageGrid
                case .hotkeys, .micPresets:
                    Text("Puoi importare profili e widget da file con \"Importa widget\".")
                        .font(.system(size: 13)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center).padding(60)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var packageGrid: some View {
        let installedIDs = Set(pm.packages.map(\.uuid))
        let list: [StoreItem] = page == .mine
            ? pm.packages.map { StoreItem(installed: $0, catalog: nil) }
            : PackageManager.catalog.map { c in StoreItem(installed: pm.packages.first { $0.uuid == c.id }, catalog: c) }
                + pm.packages.filter { p in !PackageManager.catalog.contains { $0.id == p.uuid } }.map { StoreItem(installed: $0, catalog: nil) }
        let filtered = list.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        let integrations = BuiltInIntegration.allCases.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
        let columns = [GridItem(.fixed(300), spacing: 8), GridItem(.fixed(300), spacing: 8)]
        return VStack(alignment: .leading, spacing: 10) {
            if !integrations.isEmpty {
                Text("Integrazioni incluse").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textMid)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(integrations) { IntegrationCard(integration: $0) }
                }
                Text("Pacchetti da scaricare").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textMid).padding(.top, 10)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(filtered) { item in StoreCard(item: item, installed: item.installed != nil || installedIDs.contains(item.id)) }
            }
        }
        .padding(.horizontal, 40).padding(.bottom, 20)
    }

    private func installFromFile() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        for u in p.urls { Task { await pm.install(from: u) } }
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                icon.frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name).font(.system(size: 14))
                    if !item.author.isEmpty { Text(item.author).font(.system(size: 12)).foregroundStyle(Theme.textDim) }
                    if let v = item.installed?.version { Text("v\(v)").font(.system(size: 11)).foregroundStyle(Theme.textDim) }
                    if let p = item.installed, !p.runsNatively {
                        Text("Solo Intel – non compatibile").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: "#FF9900"))
                            .help("Questo pacchetto contiene solo codice Intel: richiede Rosetta, che macOS 28 non supporta più. NexusDeck non lo avvia.")
                    }
                }
                Spacer()
            }
            .padding(14)
            Text(item.summary).font(.system(size: 13)).lineLimit(2).frame(height: 38, alignment: .topLeading).padding(.horizontal, 14)
            Rectangle().fill(Color.black).frame(height: 1).padding(.top, 10)
            HStack {
                Spacer()
                if pm.installing.contains(item.catalog?.url.absoluteString ?? "-") {
                    ProgressView().controlSize(.small).frame(width: 116, height: 31)
                } else if installed {
                    Button { pm.uninstall(item.id) } label: {
                        Text("Disinstalla").font(.system(size: 13)).foregroundStyle(Theme.textDim).frame(width: 100, height: 31).background(Color(hex: "#333333"))
                    }.buttonStyle(.plain)
                } else if let c = item.catalog {
                    Button { Task { await pm.install(from: c.url) } } label: {
                        Text("Installa").font(.system(size: 13)).foregroundStyle(.white).frame(width: 116, height: 31).background(Color(hex: "#E4002B"))
                    }.buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .background(Color(hex: "#1C1C1C"))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder private var icon: some View {
        if let p = item.installed, let img = NSImage(contentsOf: p.file(p.icon)) {
            Image(nsImage: img).resizable().scaledToFit().background(Color(hex: "#2B2B2B"))
        } else if let u = item.catalog?.iconURL {
            AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Color(hex: "#2B2B2B") }
        } else {
            ZStack { Color(hex: "#2B2B2B"); Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 24)).foregroundStyle(Theme.textDim) }
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Color(hex: integration.color)
                    Image(systemName: integration.symbol).font(.system(size: 26)).foregroundStyle(.white)
                }
                .frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 6) {
                    Text(integration.title).font(.system(size: 14))
                    Text("Inclusa in NexusDeck").font(.system(size: 12)).foregroundStyle(Theme.textDim)
                }
                Spacer()
            }
            .padding(14)
            Text(integration.summary).font(.system(size: 13)).lineLimit(2).frame(height: 38, alignment: .topLeading).padding(.horizontal, 14)
            Rectangle().fill(Color.black).frame(height: 1).padding(.top, 10)
            HStack {
                Text(enabled ? "Attiva" : "Disattivata").font(.system(size: 12)).foregroundStyle(enabled ? Color.green : Theme.textDim)
                Spacer()
                Button {
                    enabled.toggle()
                    engine.applyBuiltInIntegrations()
                } label: {
                    Text(enabled ? "Disattiva" : "Attiva").font(.system(size: 13)).foregroundStyle(enabled ? Theme.textDim : .white)
                        .frame(width: 116, height: 31).background(enabled ? Color(hex: "#333333") : Color(hex: "#E4002B"))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
        .background(Color(hex: "#1C1C1C"))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
