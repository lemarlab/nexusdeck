import SwiftUI
import AppKit

/// Visual language of the app (values in points).
enum Theme {
    // Colors: follow the Mac's light / dark appearance (macOS-style palette).
    static let accent = Color(hex: "#FF8A1F")
    static let accentDim = Color.dynamic(light: "#FFE3C7", dark: "#4F3B1C")
    static let titleLine = accent
    static let window = Color.dynamic(light: "#F2F2F5", dark: "#161618")
    static let topBar = Color.dynamic(light: "#F6F6F8", dark: "#262629")
    static let sidebar = Color.dynamic(light: "#E8E8EC", dark: "#28282C")
    static let column = Color.dynamic(light: "#FAFAFC", dark: "#1E1E21")
    static let columnHeader = column
    static let canvas = Color.dynamic(light: "#F2F2F5", dark: "#161618")
    static let panel = Color.dynamic(light: "#F7F7F9", dark: "#232326")
    static let panelHeader = Color.dynamic(light: "#F7F7F9", dark: "#232326")
    static let preview = Color.dynamic(light: "#FFFFFF", dark: "#2A2A2D")
    static let card = Color.dynamic(light: "#FFFFFF", dark: "#2A2A2D")
    static let cardBorder = Color.dynamic(light: "#000000", dark: "#FFFFFF", alpha: 0.07)
    static let field = Color.dynamic(light: "#000000", dark: "#FFFFFF", alpha: 0.06)
    static let separator = Color.dynamic(light: "#000000", dark: "#FFFFFF", alpha: 0.10)
    static let text = Color.dynamic(light: "#1D1D1F", dark: "#F5F5F7")
    static let textDim = Color.dynamic(light: "#6E6E73", dark: "#A1A1A6")
    static let textMid = Color.dynamic(light: "#3A3A3C", dark: "#D8D8DC")
    static let textFaint = Color.dynamic(light: "#A1A1A6", dark: "#6E6E73")
    static let selection = Color.dynamic(light: "#000000", dark: "#FFFFFF", alpha: 0.08)
    static let track = Color.dynamic(light: "#000000", dark: "#FFFFFF", alpha: 0.12)
    static let deviceBody = Color(hex: "#282625")
    static let devicePlate = Color(hex: "#43403E")
    static let bezel = Color(hex: "#1E1E1E")
    static let knobBlue = Color(hex: "#007DFF")
    static let tilePurple = Color(hex: "#352994")
    static let tileBlue = Color(hex: "#3D9BE9")
    static let settingsBg = Color.dynamic(light: "#F5F5F7", dark: "#1E1E20")
    static let settingsMenuSel = selection
    static let settingsFooter = Color.dynamic(light: "#ECECEF", dark: "#252527")
    static let button = Color.dynamic(light: "#E5E5EA", dark: "#2C2C2E")
    static let effectsPanel = canvas
    static let sliderCard = card
    static let deviceBlue = Color(hex: "#000826")
    static let deviceRed = Color(hex: "#0A0000")
    static let knobBlueLegacy = Color(hex: "#2F8CFF")
    static let deviceBezel = bezel

    // Metrics
    static let headerHeight: CGFloat = 44
    static let sidebarWidth: CGFloat = 45
    static let sidebarExpandedWidth: CGFloat = 321
    static let columnWidth: CGFloat = 276
    static let propertiesHeight: CGFloat = 270

    /// Tile colors per action family.
    /// One colour per library category (the whole family shares it), used for icons and new keys.
    static func tileHex(for actionID: String) -> String {
        let cat = ActionCatalog.categories.first { c in c.actions.contains { $0.id == actionID } }?.id
            ?? (actionID.hasPrefix("pkg:") ? "pkg" : "")
        return categoryHex(cat)
    }

    static func categoryHex(_ category: String) -> String {
        switch category {
        case "device": "#FF7A00"
        case "system": "#0A84FF"
        case "multi": "#5E5CE6"
        case "audio": "#FF2D55"
        case "obs": "#48484A"
        case "slobs": "#1E8C7E"
        case "youtube": "#E62117"
        case "twitch": "#9146FF"
        case "discord": "#5865F2"
        case "voicemod": "#00A88E"
        case "spotify": "#1DB954"
        case "pkg": "#3A3A3C"
        default: "#5E5CE6"
        }
    }

    /// Palette of the development builds after 0.0.7 (colour by action-ID prefix), for migration.
    static func prefixHex(for actionID: String) -> String {
        switch actionID.split(separator: ".").first.map(String.init) ?? "" {
        case "system": "#0A84FF"
        case "mixer": "#FF7A00"
        case "obs": "#48484A"
        case "slobs": "#1E8C7E"
        case "twitch": "#9146FF"
        case "youtube": "#E62117"
        case "spotify": "#1DB954"
        case "discord": "#5865F2"
        case "voicemod": "#00A88E"
        case "pkg": "#3A3A3C"
        default: "#5E5CE6"
        }
    }
    static func tileColor(for actionID: String) -> Color { Color(hex: tileHex(for: actionID)) }

    /// Mixes a hex color with white (amount 0…1).
    static func lighten(_ hex: String, _ amount: Double) -> String {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return hex }
        func mix(_ c: Int) -> Int { min(255, Int(Double(c) + (255 - Double(c)) * amount)) }
        return String(format: "#%02X%02X%02X", mix(v >> 16 & 0xFF), mix(v >> 8 & 0xFF), mix(v & 0xFF))
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static let small = Font.system(size: 11)
    static let smallBold = Font.system(size: 11, weight: .semibold)
    static let header = Font.system(size: 14, weight: .bold)
}

// MARK: - Reusable controls

/// macOS-style switch in the accent colour.
struct PillToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Capsule()
            .fill(isOn ? Theme.accent : Theme.track)
            .frame(width: 32, height: 19)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(Color.white).frame(width: 15, height: 15).padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
            .contentShape(Capsule())
            .onTapGesture { isOn.toggle() }
    }
}

/// Horizontal slider: accent fill on a soft track, white round knob.
struct ThinSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var knob: KnobStyle = .round
    var onCommit: (() -> Void)? = nil

    enum KnobStyle { case round, square }

    var body: some View {
        GeometryReader { g in
            let f = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: 4)
                Capsule().fill(Theme.accent).frame(width: max(0, g.size.width * f), height: 4)
                Circle().fill(.white).frame(width: 15, height: 15)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .offset(x: g.size.width * f - 7.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = min(max(v.location.x / g.size.width, 0), 1)
                    value = (range.lowerBound + Double(p) * (range.upperBound - range.lowerBound)).rounded()
                }
                .onEnded { _ in onCommit?() })
        }
        .frame(height: 18)
    }
}

/// Rounded push button ("Apply", "Close", ...); prominent = accent.
struct FlatButton: View {
    let title: LocalizedStringKey
    var prominent = false
    var width: CGFloat = 120
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: prominent ? .semibold : .regular))
                .frame(width: width, height: 26)
                .background(prominent ? Theme.accent : Theme.card)
                .foregroundStyle(prominent ? Color.white : (enabled ? Theme.text : Theme.textFaint))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(prominent ? .clear : Theme.cardBorder, lineWidth: 1))
                .shadow(color: .black.opacity(prominent ? 0 : 0.05), radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
    }
}

/// Dark dropdown matching the app style.
/// Dropdown shown as a clickable field (like a text field) with a chevron; the list opens below it.
/// The list lives in a borderless child panel: it opens and closes instantly, and a second click
/// on the field closes it right away.
struct DropdownField<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, LocalizedStringKey)]
    var height: CGFloat = 26
    var placeholder: LocalizedStringKey = "Seleziona…"
    @State private var id = UUID()
    @State private var anchor = DropdownAnchor()
    @ObservedObject private var dropdown = DropdownPanel.shared

    init(selection: Binding<T>, options: [(T, LocalizedStringKey)], height: CGFloat = 26) {
        _selection = selection; self.options = options; self.height = height
    }

    init(selection: Binding<T>, options: [(T, String)], height: CGFloat = 26) {
        self.init(selection: selection, options: options.map { ($0.0, LocalizedStringKey($0.1)) }, height: height)
    }

    private var current: LocalizedStringKey? { options.first { $0.0 == selection }?.1 }
    private var open: Bool { dropdown.owner == id }

    var body: some View {
        HStack(spacing: 6) {
            Text(current ?? placeholder)
                .font(.system(size: 12))
                .foregroundStyle(current == nil ? Theme.textDim : Theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: open ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(open ? Theme.accent : Theme.textMid)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(open ? Theme.accent : Theme.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .shadow(color: .black.opacity(0.04), radius: 1, y: 0.5)
        .contentShape(Rectangle())
        .background(DropdownAnchorView(box: anchor))
        .onTapGesture { toggle() }
        .onDisappear { if open { dropdown.close() } }
    }

    private func toggle() {
        if open { dropdown.close(); return }
        guard let view = anchor.view else { return }
        let selected = options.firstIndex { $0.0 == selection }
        let binding = $selection
        let opts = options
        dropdown.show(owner: id, anchor: view, rows: opts.count) {
            DropdownList(titles: opts.map(\.1), selected: selected) { i in
                binding.wrappedValue = opts[i].0
                DropdownPanel.shared.close()
            }
        }
    }
}

/// Holds the AppKit view under a dropdown field, used to place the list.
final class DropdownAnchor { weak var view: NSView? }

private struct DropdownAnchorView: NSViewRepresentable {
    let box: DropdownAnchor
    func makeNSView(context: Context) -> NSView { let v = NSView(); box.view = v; return v }
    func updateNSView(_ nsView: NSView, context: Context) { box.view = nsView }
}

/// The single open dropdown list (borderless panel attached to the window).
@MainActor
final class DropdownPanel: ObservableObject {
    static let shared = DropdownPanel()
    @Published private(set) var owner: UUID?
    private var panel: NSPanel?
    private var monitor: Any?
    private weak var anchor: NSView?

    func show<V: View>(owner: UUID, anchor: NSView, rows: Int, @ViewBuilder content: () -> V) {
        close()
        guard let window = anchor.window else { return }
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let width = max(rect.width, 160)
        let height = min(CGFloat(rows) * 28 + 8, 320)
        var origin = NSPoint(x: rect.minX, y: rect.minY - height - 2)
        // Open upwards when there is no room below.
        if let screen = window.screen, origin.y < screen.visibleFrame.minY { origin.y = rect.maxY + 2 }
        let p = NSPanel(contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.animationBehavior = .none
        let host = NSHostingView(rootView: content()
            .frame(width: width, height: height)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 1)))
        host.appearance = window.effectiveAppearance
        p.contentView = host
        window.addChildWindow(p, ordered: .above)
        panel = p
        self.anchor = anchor
        self.owner = owner
        // Clicks outside the list close it; clicks on the field itself are left to the field (toggle).
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            guard let self, let panel = self.panel else { return e }
            if e.type == .keyDown {
                if e.keyCode == 53 { self.close(); return nil }
                return e
            }
            if e.window === panel { return e }
            if let a = self.anchor, e.window === a.window {
                let pt = a.convert(e.locationInWindow, from: nil)
                if a.bounds.contains(pt) { return e }
            }
            self.close()
            return e
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        panel = nil
        owner = nil
    }
}

private struct DropdownList: View {
    let titles: [LocalizedStringKey]
    let selected: Int?
    let pick: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(titles.indices, id: \.self) { i in
                        DropdownRow(title: titles[i], selected: i == selected) { pick(i) }.id(i)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { if let selected { proxy.scrollTo(selected, anchor: .center) } }
        }
    }
}

private struct DropdownRow: View {
    let title: LocalizedStringKey
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(hover ? Color.white : Theme.accent).opacity(selected ? 1 : 0)
                Text(title).font(.system(size: 12.5)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(hover ? Theme.accent.opacity(0.85) : Color.clear)
            .foregroundStyle(hover ? Color.white : Theme.text)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Labeled dropdown for forms (property panels).
struct DropdownRowField<T: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: T
    let options: [(T, LocalizedStringKey)]

    init(title: LocalizedStringKey, selection: Binding<T>, options: [(T, LocalizedStringKey)]) {
        self.title = title; _selection = selection; self.options = options
    }

    init(title: LocalizedStringKey, selection: Binding<T>, options: [(T, String)]) {
        self.init(title: title, selection: selection, options: options.map { ($0.0, LocalizedStringKey($0.1)) })
    }

    var body: some View {
        LabeledContent(title) {
            DropdownField(selection: $selection, options: options).frame(maxWidth: .infinity)
        }
    }
}

/// Kept for existing call sites: same look as `DropdownField`.
struct DarkPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var height: CGFloat = 24
    var body: some View {
        DropdownField(selection: $selection, options: options, height: max(height, 26))
    }
}

/// Grouped settings box (System Settings style): title above, rows separated by hairlines.
struct SectionCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) {
                _VariadicView.Tree(DividedRows()) {
                    content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
        .padding(.horizontal, 24).padding(.vertical, 6)
    }
}

extension View {
    func darkField(height: CGFloat = 24) -> some View {
        self.textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Theme.text)
            .padding(.horizontal, 8).frame(height: max(height, 26)).background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}

extension Color {
    /// A colour that follows the light / dark appearance.
    static func dynamic(light: String, dark: String, alpha: Double = 1) -> Color {
        func ns(_ hex: String) -> NSColor {
            var h = hex; if h.hasPrefix("#") { h.removeFirst() }
            let v = Int(h, radix: 16) ?? 0
            return NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
        }
        let l = ns(light), d = ns(dark)
        return Color(nsColor: NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l })
    }
}
