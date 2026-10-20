import SwiftUI
import AppKit

/// Logo animation shown on the device panel when NexusDeck starts and quits (our own artwork).
struct PanelIntroCanvas: View {
    /// 0 = nothing (black), 1 = logo fully shown.
    let t: CGFloat

    var body: some View {
        let e = 1 - pow(1 - t, 3)
        ZStack {
            Color.black
            // Soft warm glow behind the logo.
            RadialGradient(colors: [Color(hex: "#FF7A00").opacity(0.35 * e), .clear], center: .center, startRadius: 0, endRadius: 260)
            VStack(spacing: 14) {
                // The app icon (same artwork as the Dock).
                Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
                    .frame(width: 190, height: 190)
                    .shadow(color: Color(hex: "#FF7A00").opacity(0.45 * e), radius: 24)
                    .scaleEffect(0.7 + 0.3 * e)
                Text("NexusDeck").font(.system(size: 44, weight: .heavy)).italic().foregroundStyle(.white)
                    .opacity(Double(max(0, (t - 0.35) / 0.65)))
                    .offset(y: 14 * (1 - e))
            }
            .opacity(Double(e))
        }
        .frame(width: PanelCanvas.size.width, height: PanelCanvas.size.height)
    }
}

@MainActor
enum PanelIntro {
    static func frame(_ t: CGFloat, quality: CGFloat = 0.55) -> Data? {
        let r = ImageRenderer(content: PanelIntroCanvas(t: t))
        r.scale = 1
        guard let cg = r.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Same length at start and quit: 12 steps, then (start) or before (quit) a short hold on the logo.
    /// Quick fade (same at start and quit) and a pause on the logo.
    static let interval: TimeInterval = 0.09
    static let hold: TimeInterval = 2
    static func frames(appearing: Bool) -> [Data] {
        let steps: [CGFloat] = [0.2, 0.45, 0.7, 0.88, 1]
        let seq = appearing ? steps : steps.reversed().dropFirst() + [0]
        return seq.compactMap { frame($0) }
    }

    // MARK: Firmware update screen

    static func updateFrame(_ progress: CGFloat) -> Data? {
        let r = ImageRenderer(content: PanelUpdateCanvas(progress: progress))
        r.scale = 1
        guard let cg = r.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.55])
    }
}

/// Panel during a firmware update: app icon, title, progress bar and percentage.
struct PanelUpdateCanvas: View {
    let progress: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#1B2A4A"), Color(hex: "#0B1426")], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 22) {
                Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 120, height: 120)
                Text("Aggiornamento firmware").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(LinearGradient(colors: [Color(hex: "#FFB340"), Color(hex: "#FF7A00")], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(14, 460 * progress))
                }
                .frame(width: 460, height: 14)
                Text(progress >= 1 ? "Completato" : "\(Int(progress * 100))%  ·  Non scollegare il mixer")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .frame(width: PanelCanvas.size.width, height: PanelCanvas.size.height)
    }
}
