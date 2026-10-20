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
    static let settingsBg = Color.dynamic(light: "#F5F5F7", dark: "#1E1E20")
    static let settingsMenuSel = selection
    static let settingsFooter = Color.dynamic(light: "#ECECEF", dark: "#252527")
    static let button = Color.dynamic(light: "#E5E5EA", dark: "#2C2C2E")
    static let effectsPanel = canvas
    static let sliderCard = card
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

    init(selection: Binding<T>, options: [(T, LocalizedStringKey)], height: CGFloat = 26) {
        _selection = selection; self.options = options; self.height = height
    }

    init(selection: Binding<T>, options: [(T, String)], height: CGFloat = 26) {
        self.init(selection: selection, options: options.map { ($0.0, LocalizedStringKey($0.1)) }, height: height)
    }

    var body: some View {
        // Native macOS pop-up menu (same look and behaviour as the system apps).
        Picker("", selection: $selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in Text(o.1).tag(o.0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
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
