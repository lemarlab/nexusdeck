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
