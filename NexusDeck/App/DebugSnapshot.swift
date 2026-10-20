#if DEBUG
import AppKit

/// Development aid: `NexusDeck.snapshot` (distributed notification, object = folder) saves a PNG of every
/// visible window of the app, so the UI can be checked without screen-recording permission.
enum DebugSnapshot {
    static func install(ui: UIState, editor: DeckEditorModel, deck: DeckController) {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("NexusDeck.section"), object: nil, queue: .main) { n in
            MainActor.assumeIsolated {
                let parts = ((n.object as? String) ?? "").split(separator: ":").map(String.init)
                if parts.first == "key", parts.count > 1, let n = Int(parts[1]) {
                    let keys = deck.keys(onPage: deck.currentPage)
                    if n < keys.count { editor.selectedKey = keys[n].id; editor.selectedKnob = nil }
                    return
                }
                if parts.first == "size", parts.count > 2, let w = Double(parts[1]), let h = Double(parts[2]),
                   let win = NSApp.windows.first(where: { $0.styleMask.contains(.titled) && $0.isVisible }) {
                    var f = win.frame; f.size = NSSize(width: w, height: h); win.setFrame(f, display: true); return
                }
                if parts.first == "mictab", parts.count > 1, let t = MicEffectTab(rawValue: parts[1]) { ui.micTab = t; return }
                if parts.first == "offline" { ui.dismissedNotFound = true; ui.loading = false; return }
                if parts.first == "lighttab" { NotificationCenter.default.post(name: Notification.Name("NexusDeck.lightTab"), object: nil); return }
                if parts.first == "settings" { ui.settingsPage = parts.count > 1 ? SettingsPage(rawValue: parts[1]) : nil; return }
                if parts.first == "action", parts.count > 1 {
                    if let k = deck.store.hotkey.keys.first(where: { $0.actionID == parts[1] }) { editor.selectedKey = k.id; editor.selectedKnob = nil }
                    return
                }
                if parts.first == "knob", parts.count > 1, let n = Int(parts[1]) { editor.selectedKnob = n; editor.selectedKey = nil; return }
                if let s = MainSection(rawValue: parts.first ?? "") { ui.section = s }
                if parts.count > 1, let k = Int(parts[1]) { ui.mixerKnob = k }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("NexusDeck.snapshot"), object: nil, queue: .main) { n in
            let folder = (n.object as? String) ?? NSTemporaryDirectory()
            MainActor.assumeIsolated {
                let all = NSApp.windows + NSApp.windows.compactMap(\.attachedSheet)
                for (i, w) in all.enumerated() where w.isVisible || w.isSheet {
                    guard let v = w.contentView?.superview ?? w.contentView,
                          let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                    v.cacheDisplay(in: v.bounds, to: rep)
                    let url = URL(fileURLWithPath: folder).appendingPathComponent("win\(i).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
        }
        // Optional: switch appearance for checks ("light" / "dark" / "auto").
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("NexusDeck.appearance"), object: nil, queue: .main) { n in
            MainActor.assumeIsolated {
                switch n.object as? String {
                case "light": NSApp.appearance = NSAppearance(named: .aqua)
                case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                default: NSApp.appearance = nil
                }
            }
        }
    }
}
#endif
