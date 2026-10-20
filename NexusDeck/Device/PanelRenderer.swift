import SwiftUI
import AppKit

/// Full 800x480 touch panel image, laid out as a 5x4 grid.
struct PanelCanvas: View {
    @ObservedObject var deck: DeckController
    @ObservedObject var store: ProfileStore
    var images: [UUID: NSImage] = [:]
    var touchedKey: UUID?
    /// Page to draw (default: the current one) and whether to draw the background (the editor slides the keys over a fixed background).
    var page: Int? = nil
    var drawsBackground = true

    static let size = CGSize(width: AXProtocol.panelWidth, height: AXProtocol.panelHeight)
    static let cellW: CGFloat = size.width / 5
    static let cellH: CGFloat = size.height / 4
    static let inset: CGFloat = 5
    static let radius: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topLeading) {
            if drawsBackground { background } else { Color.clear.frame(width: Self.size.width, height: Self.size.height) }
            if drawsBackground && deck.panelOn && !store.library.device.autoHideGrid {
                ForEach(0..<20, id: \.self) { i in
                    // Empty place: a soft glassy tile (no dashed border).
                    RoundedRectangle(cornerRadius: Self.radius)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.07 * store.library.device.panelOpacity),
                                                      Color.white.opacity(0.03 * store.library.device.panelOpacity)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: Self.radius).strokeBorder(Color.white.opacity(0.06 * store.library.device.panelOpacity), lineWidth: 1))
                        .frame(width: Self.cellW - 2 * Self.inset, height: Self.cellH - 2 * Self.inset)
                        .offset(x: CGFloat(i % 5) * Self.cellW + Self.inset, y: CGFloat(i / 5) * Self.cellH + Self.inset)
                }
            }
            if deck.panelOn {
                ForEach(deck.keys(onPage: page ?? deck.currentPage)) { k in
                    face(k)
                        .frame(width: CGFloat(k.w) * Self.cellW - 2 * Self.inset, height: CGFloat(k.h) * Self.cellH - 2 * Self.inset)
                        .clipShape(RoundedRectangle(cornerRadius: Self.radius))
                        .scaleEffect(touchedKey == k.id && store.library.device.touchEffect ? 0.92 : 1)
                        .offset(x: CGFloat(k.x) * Self.cellW + Self.inset, y: CGFloat(k.y) * Self.cellH + Self.inset)
                        .transition(.scale(scale: 0.8, anchor: .center).combined(with: .opacity))
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environmentObject(deck)
        .environmentObject(store)
    }

    @ViewBuilder private var background: some View {
        let bg = store.library.device.background
        if bg.mode == .image, let img = ImageCache.image(atPath: bg.imagePath) {
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
        guard let cg = image(deck: deck, store: store, images: images, touched: touched) else { return nil }
        return encode(cg, quality: quality)
    }

    /// One layer of a page slide: the background only, or the keys of a page on a transparent background.
    static func layer(deck: DeckController, store: ProfileStore, images: [UUID: NSImage], page: Int, background: Bool) -> CGImage? {
        autoreleasepool {
            let r = ImageRenderer(content: PanelCanvas(deck: deck, store: store, images: images, page: page, drawsBackground: background))
            r.scale = 1
            r.isOpaque = background
            return r.cgImage
        }
    }

    /// A frame of the page slide composed from the three layers (any thread).
    nonisolated static func slide(bg: CGImage, old: CGImage, new: CGImage, forward: Bool, progress: CGFloat) -> CGImage? {
        let w = bg.width, h = bg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let d: CGFloat = forward ? 1 : -1, W = CGFloat(w)
        ctx.draw(bg, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(old, in: CGRect(x: -d * progress * W, y: 0, width: W, height: CGFloat(h)))
        ctx.draw(new, in: CGRect(x: d * (1 - progress) * W, y: 0, width: W, height: CGFloat(h)))
        return ctx.makeImage()
    }

    /// Draws the panel (SwiftUI, main thread).
    static func image(deck: DeckController, store: ProfileStore, images: [UUID: NSImage], touched: UUID?) -> CGImage? {
        autoreleasepool {
            let r = ImageRenderer(content: PanelCanvas(deck: deck, store: store, images: images, touchedKey: touched))
            r.scale = 1
            return r.cgImage
        }
    }

    /// JPEG for the device (any thread), lowering the quality if the frame is too big.
    nonisolated static func encode(_ cg: CGImage, quality: CGFloat) -> Data? {
        autoreleasepool {
            let rep = NSBitmapImageRep(cgImage: cg)
            var q = quality
            while q > 0.2 {
                if let d = rep.representation(using: .jpeg, properties: [.compressionFactor: q]), d.count <= AXProtocol.maxFrameBytes { return d }
                q -= 0.15
            }
            return nil
        }
    }
}
