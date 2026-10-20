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
    /// The blur of the other page stays only during the switch (each copy re-renders the whole drawing).
    @State private var shown: Set<Mode> = []

    func body(content: Content) -> some View {
        let keys = mode == .knobs
        content
            .overlay {
                GeometryReader { g in
                    let k = g.size.height / 599
                    ZStack(alignment: .top) {
                        if shown.contains(.knobs) {
                            band(content, radius: 4, from: 440, to: 599, k: k, size: g.size,
                                 stops: [(0, 0), (472, 0), (540, 1), (599, 1)]).opacity(keys ? 1 : 0)
                        }
                        if shown.contains(.top) {
                            band(content, radius: 7, from: 0, to: 400, k: k, size: g.size,
                                 stops: [(0, 1), (290, 1), (385, 0), (400, 0)]).opacity(keys ? 0 : 1)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.88), value: keys)
            .onAppear { shown = [mode] }
            .onChange(of: mode) { _, m in
                shown.insert(m)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if mode == m { shown = [m] } }
            }
    }

    /// Blurred copy of only the band `from…to` (design units): blurring the small band is much cheaper than
    /// the whole drawing. `stops` give the visibility along the band.
    private func band(_ content: Content, radius: CGFloat, from: CGFloat, to: CGFloat, k: CGFloat, size: CGSize,
                      stops: [(CGFloat, Double)]) -> some View {
        let h = (to - from) * k
        let gs = stops.map { Gradient.Stop(color: .black.opacity($0.1), location: ($0.0 - from) / (to - from)) }
        return content
            .frame(width: size.width, height: size.height)
            .offset(y: -from * k)
            .frame(width: size.width, height: h, alignment: .top)
            .clipped()
            .blur(radius: radius)
            .mask(LinearGradient(stops: gs, startPoint: .top, endPoint: .bottom))
            .offset(y: from * k)
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
