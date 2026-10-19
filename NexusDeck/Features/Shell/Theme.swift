import SwiftUI
import AppKit

/// Visual language measured from the reference screenshots (values in points).
enum Theme {
    // Colors
    static let accent = Color(hex: "#FF9900")
    static let accentDim = Color(hex: "#4F3B1C")
    static let titleLine = Color(hex: "#BF7F33")
    static let window = Color(hex: "#000000")
    static let topBar = Color(hex: "#2D2D2D")
    static let sidebar = Color(hex: "#363636")
    static let column = Color(hex: "#232323")
    static let columnHeader = Color(hex: "#282828")
    static let canvas = Color(hex: "#000000")
    static let panel = Color(hex: "#282828")
    static let panelHeader = Color(hex: "#242424")
    static let preview = Color(hex: "#1E1E1E")
    static let card = Color(hex: "#323232")
    static let field = Color(hex: "#1E1E1E")
    static let separator = Color(hex: "#474747")
    static let text = Color(hex: "#FFFFFF")
    static let textDim = Color(hex: "#A1A1A1")
    static let textMid = Color(hex: "#C8C8C8")
    static let deviceBody = Color(hex: "#282625")
    static let devicePlate = Color(hex: "#43403E")
    static let bezel = Color(hex: "#1E1E1E")
    static let knobBlue = Color(hex: "#007DFF")
    static let tilePurple = Color(hex: "#352994")
    static let tileBlue = Color(hex: "#3D9BE9")
    static let settingsBg = Color(hex: "#292929")
    static let settingsMenuSel = Color(hex: "#3C3C3C")
    static let settingsFooter = Color(hex: "#252525")
    static let button = Color(hex: "#1B1D1D")
    static let effectsPanel = Color(hex: "#292929")
    static let sliderCard = Color(hex: "#1E1E1E")
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
    static func tileHex(for actionID: String) -> String {
        switch actionID.split(separator: ".").first.map(String.init) ?? "" {
        case "system": "#3D9BE9"
        case "obs": "#5B5B66"
        case "slobs": "#1E8C7E"
        case "twitch": "#7C3AED"
        case "youtube": "#C62828"
        case "spotify": "#1E7F3C"
        case "discord": "#4752C4"
        case "voicemod": "#00897B"
        case "pkg": "#2B2B2B"
        default: "#352994"
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

/// Small orange pill toggle.
struct PillToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Capsule()
            .fill(isOn ? Theme.accent : Color.white.opacity(0.18))
            .frame(width: 18, height: 10)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(isOn ? Color.white : Color(hex: "#9A9A9A")).frame(width: 6, height: 6).padding(2)
            }
            .overlay(Capsule().strokeBorder(isOn ? .clear : Color(hex: "#7A7A7A"), lineWidth: 1))
            .animation(.easeInOut(duration: 0.12), value: isOn)
            .onTapGesture { isOn.toggle() }
    }
}

/// Thin horizontal slider: orange fill, brown track, white round knob.
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
                Capsule().fill(Theme.accentDim).frame(height: 2)
                Capsule().fill(Theme.accent).frame(width: max(0, g.size.width * f), height: 2)
                Circle().fill(.white).frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.4), radius: 1)
                    .offset(x: g.size.width * f - 5)
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
        .frame(height: 14)
    }
}

/// Flat dark button used in dialogs ("Apply", "Close", ...).
struct FlatButton: View {
    let title: LocalizedStringKey
    var prominent = false
    var width: CGFloat = 120
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12))
                .frame(width: width, height: 24)
                .background(prominent ? Theme.accent : Theme.button)
                .foregroundStyle(prominent ? Color.black : (enabled ? Theme.textMid : Color(hex: "#555555")))
                .clipShape(RoundedRectangle(cornerRadius: 2))
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
        .background(Theme.field)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(open ? Theme.accent : Color.white.opacity(0.10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
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
            .background(Color(hex: "#232323"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .preferredColorScheme(.dark))
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
                    .foregroundStyle(Theme.accent).opacity(selected ? 1 : 0)
                Text(title).font(.system(size: 12)).foregroundStyle(selected ? Theme.text : Theme.textMid).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(hover ? Theme.accent.opacity(0.22) : Color.clear)
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
            DropdownField(selection: $selection, options: options).frame(minWidth: 180, maxWidth: 280)
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

struct SectionCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textMid)
            content
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
    }
}

extension View {
    func darkField(height: CGFloat = 24) -> some View {
        self.textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.text)
            .padding(.horizontal, 6).frame(height: height).background(Theme.field)
    }
}
