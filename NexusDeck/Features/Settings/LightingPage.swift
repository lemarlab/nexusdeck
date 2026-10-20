import SwiftUI

/// Sidebar page "Illuminazione": custom lighting (device preview, zone cards, zone settings) and interactive lighting.
struct LightingPage: View {
    @EnvironmentObject var store: ProfileStore
    @State private var tab = 0
    @State private var area: LightingArea = .knobs

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                seg("Personalizzata", 0)
                seg("Interattiva", 1)
            }
            .padding(2)
            .background(Theme.field)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: 320)
            .padding(.top, 18).padding(.bottom, 6)
            ScrollView {
                if tab == 0 {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 14) {
                            LightingPreview(area: $area)
                            zoneCards
                        }
                        .frame(width: 430)
                        .padding(.leading, 28)
                        CustomLightingPage(area: $area)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 14)
                } else {
                    InteractiveLightingPage()
                        .frame(maxWidth: 820)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NexusDeck.lightTab"))) { _ in tab = 1 }
        #endif
    }

    private var zoneCards: some View {
        let d = store.library.device
        let zones: [(LightingArea, String, String, String, String)] = [
            (.screen, "Schermo", "rectangle.grid.3x2.fill", "#5E5CE6", "Luminosità \(d.brightness)%"),
            (.keys, "Tasti", "square.fill", "#FF8A1F", Self.summary(d.ledButton)),
            (.knobs, "Manopole", "circle.circle.fill", "#0A84FF", Self.summary(d.ledKnob)),
            (.strip, "Striscia", "minus", "#FF3B30", Self.summary(d.ledAura)),
        ]
        return HStack(spacing: 8) {
            ForEach(zones, id: \.1) { z in
                let on = area == z.0
                Button { withAnimation(.easeOut(duration: 0.15)) { area = z.0 } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        SidebarIcon(symbol: z.2, tint: Color(hex: z.3))
                        Text(z.1).font(.system(size: 12.5, weight: .semibold))
                        Text(z.4).font(.system(size: 11)).foregroundStyle(Theme.textDim).lineLimit(1)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Theme.accent : Theme.cardBorder, lineWidth: on ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    static func summary(_ l: LEDSetting) -> String {
        switch l.mode {
        case .off: return "Spento"
        case .volume: return "Livello volume"
        case .wave: return "Arcobaleno"
        case .colorCycle: return "Ciclo colori"
        case .spectrum: return "Onda colori"
        case .rainbow: return "Respiro"
        case .flash: return "Pulsante"
        default:
            switch l.colorSource {
            case .widget: return "Colore widget"
            case .perItem: return "Un colore ciascuno"
            case .single: return "Statico"
            }
        }
    }

    private func seg(_ t: LocalizedStringKey, _ i: Int) -> some View {
        let on = tab == i
        return Button { withAnimation(.easeOut(duration: 0.15)) { tab = i } } label: {
            Text(t).font(.system(size: 12.5, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.text : Theme.textDim)
                .frame(maxWidth: .infinity).frame(height: 26)
                .background(on ? Theme.card : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 0.5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Small drawing of the AX310 with its lights in their current colours; clicking a part selects its zone.
struct LightingPreview: View {
    @Binding var area: LightingArea
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService

    var body: some View {
        let d = store.library.device
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                // Touch screen
                RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#0C0C0D"))
                    .overlay(
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                            ForEach(0..<20, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [Color(hex: "#FFA24D"), Color(hex: "#FF7A00")], startPoint: .top, endPoint: .bottom))
                                    .opacity(i % 3 == 2 ? 0.25 : 0.85 * Double(d.brightness) / 100 + 0.15)
                                    .frame(height: 26)
                            }
                        }
                        .padding(7)
                    )
                    .frame(width: 250, height: 148)
                    .modifier(ZoneOutline(on: area == .screen))
                    .onTapGesture { area = .screen }
                // Function keys
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        let c = keyColor(i)
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [Color(hex: "#3A3A3E"), Color(hex: "#232326")], startPoint: .top, endPoint: .bottom))
                            .frame(height: 66)
                            .overlay(alignment: .bottom) {
                                Capsule().fill(c).frame(width: 26, height: 3).shadow(color: c, radius: 4).padding(.bottom, 8)
                            }
                    }
                }
                .modifier(ZoneOutline(on: area == .keys))
                .onTapGesture { area = .keys }
            }
            HStack {
                ForEach(0..<6, id: \.self) { i in
                    let c = d.ledKnob.mode == .off ? Color.clear : d.ledKnob.knobColor(i)
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: "#434347"), Color(hex: "#1D1D20")], center: .top, startRadius: 1, endRadius: 24))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(c, lineWidth: 4).padding(-3))
                        .shadow(color: c.opacity(0.7), radius: 5)
                    if i < 5 { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .modifier(ZoneOutline(on: area == .knobs))
            .onTapGesture { area = .knobs }
            Capsule()
                .fill(stripStyle(d.ledAura))
                .frame(height: 6)
                .shadow(color: Color(hex: d.ledAura.colorHex).opacity(d.ledAura.mode == .off ? 0 : 0.7), radius: 6)
                .padding(.vertical, 4)
                .modifier(ZoneOutline(on: area == .strip))
                .onTapGesture { area = .strip }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color(hex: "#2E2E31"), Color(hex: "#18181A")], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
        )
    }

    private func keyColor(_ i: Int) -> Color {
        let l = store.library.device.ledButton
        guard l.mode != .off else { return .clear }
        switch l.colorSource {
        case .perItem: return Color(hex: l.itemColors[min(i, l.itemColors.count - 1)])
        case .single: return Color(hex: l.colorHex)
        case .widget: return Color(hex: audio.functionKeyColors()[i] ?? "#000000")
        }
    }

    private func stripStyle(_ l: LEDSetting) -> AnyShapeStyle {
        switch l.mode {
        case .off: return AnyShapeStyle(Color.white.opacity(0.08))
        case .wave, .colorCycle, .spectrum:
            return AnyShapeStyle(LinearGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple], startPoint: .leading, endPoint: .trailing))
        default: return AnyShapeStyle(Color(hex: l.colorHex))
        }
    }
}

private struct ZoneOutline: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        content
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Theme.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
    }
}
