import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 8 {
            self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: Double((v >> 24) & 0xFF) / 255)
        } else {
            self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        }
    }

    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// Loads the image referenced by a KeyState (SF Symbol or user file).
struct KeyImage: View {
    let ref: String
    /// Built-in symbols leave room for the title below, as in the reference layout (50×50 icon in a 150×108 key).
    var hasTitle = true
    var body: some View {
        if ref.hasPrefix("file:"), let img = NSImage(contentsOfFile: String(ref.dropFirst(5))) {
            Image(nsImage: img).resizable().scaledToFit()
        } else if ref.hasPrefix("sf:") {
            GeometryReader { g in
                let side = min(g.size.width, g.size.height) * 0.52
                Image(systemName: String(ref.dropFirst(3)))
                    .resizable().scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: side, height: side)
                    .position(x: g.size.width / 2, y: g.size.height * (hasTitle ? 0.38 : 0.5))
            }
        } else if !ref.isEmpty, let img = NSImage(contentsOf: ProfileStore.iconFolder.appendingPathComponent(ref)) {
            Image(nsImage: img).resizable().scaledToFill()
        } else {
            Color.clear
        }
    }
}

/// Face of a single key, as shown in the editor and sent to the device.
struct KeyFaceView: View {
    let state: KeyState
    let style: KeyTitleStyle
    var overlayText: String? = nil

    var body: some View {
        if state.image.hasPrefix("sf:") {
            symbolFace
        } else {
            standardFace
        }
    }

    /// Built-in icon + title, laid out like the tile dragged from the action list
    /// (icon ≈ 36% of the key height, title ≈ 23% at the default size), so it looks the same at any scale.
    private var symbolFace: some View {
        GeometryReader { g in
            let h = g.size.height
            let titleSize = h * 0.15 * style.size / 13
            ZStack {
                // Soft vertical gradient of the key colour, like the app icons of macOS.
                LinearGradient(colors: [Color(hex: Theme.lighten(state.background, 0.14)), Color(hex: state.background)],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: h * 0.05) {
                    Image(systemName: String(state.image.dropFirst(3)))
                        .font(.system(size: h * (overlayText == nil ? 0.3 : 0.24), weight: .medium))
                        .foregroundStyle(.white)
                    if let live = overlayText {
                        // Live value (CPU, counters, now playing…) in place of the title.
                        Text(live)
                            .font(.system(size: h * 0.2, weight: .bold))
                            .foregroundStyle(Color(hex: style.colorHex))
                            .lineLimit(3).minimumScaleFactor(0.35)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, h * 0.05)
                    } else if !state.title.isEmpty {
                        Text(state.title.uppercased())
                            .font(style.fontFamily.isEmpty ? .system(size: titleSize, weight: style.bold ? .heavy : .bold) : .custom(style.fontFamily, size: titleSize).weight(.bold))
                            .tracking(titleSize * 0.04)
                            .italic(style.italic)
                            .underline(style.underline)
                            .foregroundStyle(Color(hex: style.colorHex))
                            .lineLimit(2).minimumScaleFactor(0.6)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, h * 0.05)
                    }
                }
                .frame(width: g.size.width, height: h)
            }
        }
        .clipped()
    }

    private var standardFace: some View {
        ZStack {
            Color(hex: state.background)
            KeyImage(ref: state.image, hasTitle: !state.title.isEmpty)
            if let overlayText {
                GeometryReader { g in
                    Text(overlayText).font(.system(size: g.size.height * 0.2, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(3).minimumScaleFactor(0.35).multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.8), radius: 1)
                        .frame(width: g.size.width, height: g.size.height)
                }
            }
            if !state.title.isEmpty {
                VStack {
                    if style.alignment != .top { Spacer(minLength: 0) }
                    Text(state.title)
                        .font(style.fontFamily.isEmpty ? .system(size: style.size, weight: style.bold ? .bold : .regular) : .custom(style.fontFamily, size: style.size).weight(style.bold ? .bold : .regular))
                        .italic(style.italic)
                        .underline(style.underline)
                        .foregroundStyle(Color(hex: style.colorHex))
                        .lineLimit(2)
                        .multilineTextAlignment(style.textAlignment == .leading ? .leading : (style.textAlignment == .trailing ? .trailing : .center))
                        .frame(maxWidth: .infinity, alignment: style.textAlignment == .leading ? .leading : (style.textAlignment == .trailing ? .trailing : .center))
                        .shadow(color: .black.opacity(0.8), radius: 1)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 4)
                    if style.alignment != .bottom { Spacer(minLength: 0) }
                }
            }
        }
        .clipped()
    }
}
