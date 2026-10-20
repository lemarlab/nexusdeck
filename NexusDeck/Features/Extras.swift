import SwiftUI
import WebKit

/// Periodically snapshots web pages for WebView widgets shown on the panel.
@MainActor
final class WebSnapshotter: NSObject, WKNavigationDelegate {
    /// Default style of the reference app: transparent page, centered, no scroll bars.
    static let defaultCSS = "body { background-color: rgba(0, 0, 0, 0); margin: 0px auto; overflow: hidden; }"
    /// Widget sizes offered by the reference app.
    static let layouts: [(w: Int, h: Int)] = [(2, 1), (2, 2), (4, 3), (2, 4), (3, 4), (5, 4)]

    private var views: [UUID: WKWebView] = [:]
    private var urls: [UUID: String] = [:]
    private var css: [UUID: String] = [:]
    private var interactive: NSWindow?
    var onImage: ((UUID, NSImage) -> Void)?

    static func normalized(_ url: String) -> URL? {
        var s = url.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty, !s.contains("://") { s = "https://" + s }
        return URL(string: s).flatMap { $0.scheme == nil ? nil : $0 }
    }

    func update(keys: [KeyAssignment]) {
        let web = keys.filter { $0.actionID == ActionID.webView }
        for id in views.keys where !web.contains(where: { $0.id == id }) { views[id] = nil; urls[id] = nil; css[id] = nil }
        for k in web {
            let url = k.settings.string("url")
            let size = CGSize(width: CGFloat(k.w) * 160, height: CGFloat(k.h) * 120)
            let v = views[k.id] ?? {
                let w = WKWebView(frame: CGRect(origin: .zero, size: size))
                w.setValue(false, forKey: "drawsBackground")
                w.navigationDelegate = self
                return w
            }()
            v.frame.size = size
            views[k.id] = v
            let style = k.settings.string("customCss", Self.defaultCSS)
            if css[k.id] != style { css[k.id] = style; inject(v, style) }
            if urls[k.id] != url, let u = Self.normalized(url) {
                urls[k.id] = url
                v.load(URLRequest(url: u))
            }
        }
    }

    /// "Refresh the page".
    func reload(_ id: UUID) { views[id]?.reload() }

    private func inject(_ v: WKWebView, _ style: String) {
        let escaped = style.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: " ")
        let js = "(function(){var c=document.getElementById('nexusdeck-css');if(!c){c=document.createElement('style');c.id='nexusdeck-css';document.head.appendChild(c);}c.innerText='\(escaped)';})();"
        v.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let id = views.first(where: { $0.value === webView })?.key { inject(webView, css[id] ?? Self.defaultCSS) }
    }

    /// "Interact": a normal browser window sharing cookies with the widget (to sign in, accept dialogs…).
    func openInteractive(_ url: String) {
        guard let u = Self.normalized(url) else { return }
        let w = interactive ?? {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 720), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            win.isReleasedWhenClosed = false
            win.title = "Browser interattivo"
            win.contentView = WKWebView(frame: .zero)
            win.center()
            return win
        }()
        interactive = w
        (w.contentView as? WKWebView)?.load(URLRequest(url: u))
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func snapshotAll() {
        for (id, v) in views where !v.isLoading {
            v.takeSnapshot(with: nil) { [weak self] img, _ in
                if let img { self?.onImage?(id, img) }
            }
        }
    }
}

struct TutorialView: View {
    @EnvironmentObject var store: ProfileStore
    @State private var page = 0

    private let pages: [(String, String, String)] = [
        ("square.grid.3x3.fill", "Widget", "Trascina azioni e widget dalla libreria sugli slot del pannello touch. Usa le pagine e le cartelle per organizzarli; fai swipe a sinistra/destra sul dispositivo per cambiare pagina."),
        ("dial.medium.fill", "Manopole", "Ogni manopola controlla un canale del mixer hardware: girala per il volume, premila per il muto. Puoi assegnarle anche ad altre funzioni."),
        ("slider.vertical.3", "Mixer audio", "Regola i due mix (Creator e Audience), il monitor del microfono e le uscite cuffie e linea."),
        ("mic.fill", "Microfono", "Equalizzatore, noise gate, compressore, riverbero ed eco vengono elaborati dal DSP del dispositivo."),
        ("puzzlepiece.extension.fill", "Integrazioni", "Collega OBS, Streamlabs, Twitch, YouTube e Spotify per controllarli dai tasti."),
    ]

    var body: some View {
        VStack(spacing: 20) {
            let p = pages[page]
            Image(systemName: p.0).font(.system(size: 64)).foregroundStyle(.tint).frame(height: 90)
            Text(p.1).font(.title.bold())
            Text(p.2).multilineTextAlignment(.center).frame(maxWidth: 420).foregroundStyle(.secondary)
            HStack(spacing: 6) { ForEach(pages.indices, id: \.self) { Circle().fill($0 == page ? Color.accentColor : .gray.opacity(0.4)).frame(width: 7, height: 7) } }
            HStack {
                Button("Salta") { store.library.tutorialDone = true }
                Spacer()
                if page > 0 { Button("Indietro") { page -= 1 } }
                Button(page == pages.count - 1 ? "Inizia" : "Avanti") {
                    if page == pages.count - 1 { store.library.tutorialDone = true } else { page += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 560, height: 400)
    }
}
