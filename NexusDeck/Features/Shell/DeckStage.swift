import SwiftUI

/// Tasti e widget and Mixer share one stage: the device drawing, with a translucent panel below it.
/// Keys: the whole device is visible and the panel (key settings) covers the lower half of the knobs,
/// which fade into it. Mixer: the device slides up, the display fades out at the top, the knobs stay sharp
/// and the panel with the mixer settings rises below them.
struct DeckStage: View {
    @EnvironmentObject var ui: UIState
    private var mixer: Bool { ui.section == .mixer }

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            // Device scale: fits the width and leaves room for the key panel.
            // Fixed size, the same on both pages (it does not change with the window).
            let s: CGFloat = 0.95
            let devW = DeviceCanvas.design.width * s, devH = DeviceCanvas.design.height * s
            // Design coordinates (of the 803 × 599 drawing): knob row ≈ 415…545, display bottom ≈ 386.
            let devTop: CGFloat = mixer ? 28 - 352 * s : 14
            let panelTop: CGFloat = mixer ? devTop + 600 * s : devTop + 528 * s
            // Layout by padding (not absolute offsets): the panel always fits the stage, inset 20 pt each side.
            ZStack(alignment: .top) {
                DeviceCanvas()
                    .frame(width: devW, height: devH)
                    .modifier(ProgressiveFog(mode: mixer ? .top : .knobs))
                    .offset(y: devTop)
                    .frame(width: W, alignment: .top)
                StagePanel(mixer: mixer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, panelTop)
                    .padding(.bottom, 16)
            }
            .frame(width: W, height: H, alignment: .top)
            .clipped()
        }
    }
}

/// Progressive blur over part of the device drawing (translucent material, light where it starts and
/// strong towards the edge it fades into): the knobs on the keys page, the display on the mixer page.
private struct ProgressiveFog: ViewModifier {
    enum Mode: Equatable { case knobs, top }
    let mode: Mode

    func body(content: Content) -> some View {
        // Blurred copies of the drawing, each visible over its band (the material overlay alone does not
        // blur the drawing below it).
        // Both blurs are always there and cross-fade with the same spring that moves the device, so they
        // follow it instead of popping in or lingering.
        let keys = mode == .knobs
        ZStack {
            content
            blurred(content, 2.5, [(0.0, 0), (470, 0), (505, 1), (1, 1)]).opacity(keys ? 1 : 0)
            blurred(content, 6, [(0.0, 0), (500, 0), (545, 1), (1, 1)]).opacity(keys ? 1 : 0)
            blurred(content, 8, [(0.0, 1), (250, 1), (350, 0), (1, 0)]).opacity(keys ? 0 : 1)
            blurred(content, 3, [(0.0, 1), (330, 1), (385, 0), (1, 0)]).opacity(keys ? 0 : 1)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.88), value: keys)
    }

    /// Stops in drawing units (y of the 599-high design; 0 and 1 = edges) with the copy's opacity.
    private func blurred(_ content: Content, _ radius: CGFloat, _ stops: [(CGFloat, Double)]) -> some View {
        let gs = stops.map { y, o -> Gradient.Stop in
            Gradient.Stop(color: .black.opacity(o), location: y <= 1 ? y : y / 599)
        }
        return content
            .blur(radius: radius)
            .mask(LinearGradient(stops: gs, startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }
}

/// Translucent panel under the device: key settings, or the mixer settings.
private struct StagePanel: View {
    let mixer: Bool

    var body: some View {
        // Both contents are laid out at the panel's size (the hidden one must not make the panel wider).
        ZStack {
            PropertiesPanel()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .opacity(mixer ? 0 : 1)
                .offset(y: mixer ? 40 : 0)
                .allowsHitTesting(!mixer)
            HStack(spacing: 0) {
                MixerPage()
                Rectangle().fill(Theme.separator).frame(width: 0.5)
                ChannelInspector().frame(width: 280)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            .opacity(mixer ? 1 : 0)
            .offset(y: mixer ? 0 : 60)
            .allowsHitTesting(mixer)
        }
        .padding(.top, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
    }
}
