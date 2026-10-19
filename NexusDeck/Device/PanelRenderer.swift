import SwiftUI
import AppKit

/// Full 800x480 touch panel image, laid out as a 5x4 grid.
struct PanelCanvas: View {
    @ObservedObject var deck: DeckController
    @ObservedObject var store: ProfileStore
    var images: [UUID: NSImage] = [:]
    var touchedKey: UUID?

    static let size = CGSize(width: AXProtocol.panelWidth, height: AXProtocol.panelHeight)
    static let cellW: CGFloat = size.width / 5
    static let cellH: CGFloat = size.height / 4
    static let inset: CGFloat = 3.5

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            if deck.panelOn && !store.library.device.autoHideGrid {
                ForEach(0..<20, id: \.self) { i in
                    Rectangle()
                        .fill(Color.black.opacity(0.45 * store.library.device.panelOpacity))
                        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.08 * store.library.device.panelOpacity)))
                        .frame(width: Self.cellW - 2 * Self.inset, height: Self.cellH - 2 * Self.inset)
                        .offset(x: CGFloat(i % 5) * Self.cellW + Self.inset, y: CGFloat(i / 5) * Self.cellH + Self.inset)
                }
            }
            if deck.panelOn {
                ForEach(deck.keys(onPage: deck.currentPage)) { k in
                    face(k)
                        .frame(width: CGFloat(k.w) * Self.cellW - 2 * Self.inset, height: CGFloat(k.h) * Self.cellH - 2 * Self.inset)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .scaleEffect(touchedKey == k.id && store.library.device.touchEffect ? 0.92 : 1)
                        .offset(x: CGFloat(k.x) * Self.cellW + Self.inset, y: CGFloat(k.y) * Self.cellH + Self.inset)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environmentObject(deck)
        .environmentObject(store)
    }

    @ViewBuilder private var background: some View {
        let bg = store.library.device.background
        if bg.mode == .image, let img = NSImage(contentsOfFile: bg.imagePath) {
            ZStack {
                Color(hex: bg.colorHex)
                switch bg.displayMode {
                case 1: Image(nsImage: img).resizable().scaledToFit()
                case 2: Image(nsImage: img).resizable()
                case 3: Image(nsImage: img).resizable(resizingMode: .tile)
                case 4: Image(nsImage: img)
                default: Image(nsImage: img).resizable().scaledToFill()
                }
            }
            .frame(width: Self.size.width, height: Self.size.height).clipped()
        } else {
            Color(hex: bg.colorHex)
        }
    }

    @ViewBuilder private func face(_ k: KeyAssignment) -> some View {
        if let img = images[k.id] {
            GeometryReader { g in
                ZStack {
                    Color.black
                    Image(nsImage: img).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
                    if !deck.state(for: k).title.isEmpty {
                        VStack {
                            Spacer()
                            Text(deck.state(for: k).title).font(.system(size: min(g.size.height, g.size.width * 0.75) * 0.17, weight: .bold))
                                .foregroundStyle(.white).shadow(color: .black, radius: 2).lineLimit(2).minimumScaleFactor(0.6)
                                .padding(min(g.size.height, g.size.width) * 0.05)
                        }
                    }
                }
            }
        } else {
            WidgetOrKeyView(key: k)
        }
    }
}

@MainActor
enum PanelRenderer {
    static func jpeg(deck: DeckController, store: ProfileStore, images: [UUID: NSImage], touched: UUID?, quality: CGFloat = 0.8) -> Data? {
        let r = ImageRenderer(content: PanelCanvas(deck: deck, store: store, images: images, touchedKey: touched))
        r.scale = 1
        guard let cg = r.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        var q = quality
        while q > 0.2 {
            if let d = rep.representation(using: .jpeg, properties: [.compressionFactor: q]), d.count <= AXProtocol.maxFrameBytes { return d }
            q -= 0.15
        }
        return nil
    }
}
