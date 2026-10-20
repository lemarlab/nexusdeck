import SwiftUI

/// Interactive illustration of the controller (layout measured from the reference, in points).
struct DeviceCanvas: View {
    static let design = CGSize(width: 803, height: 599)
    @EnvironmentObject var editor: DeckEditorModel
    @EnvironmentObject var deck: DeckController
    @State private var swipe = PageSwipeTracker()

    var body: some View {
        GeometryReader { g in
            // Clicking the empty area around the device clears the selection.
            Color.clear.contentShape(Rectangle())
                .onTapGesture { if !deck.swipeJustHappened { editor.selectedKey = nil; editor.selectedKnob = nil } }
            let scale = min(g.size.width / Self.design.width, g.size.height / Self.design.height)
            DeviceBody()
                .frame(width: Self.design.width, height: Self.design.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: g.size.width, height: g.size.height)
                .background(SwipeAnchor(tracker: swipe))
                .onAppear { swipe.attach(deck: deck, pageWidth: { L.lcd.width * scale }) }
                .onChange(of: scale) { swipe.attach(deck: deck, pageWidth: { L.lcd.width * scale }) }
                .onDisappear { swipe.detach() }
        }
    }
}

private enum L {
    static let device = CGRect(x: 26, y: 30, width: 746, height: 518)
    static let screenPlate = CGRect(x: 26, y: 77, width: 501, height: 319)
    static let keyPlate = CGRect(x: 527, y: 100, width: 245, height: 273)
    static let bezel = CGRect(x: 48, y: 87, width: 468, height: 299)
    static let lcd = CGRect(x: 86, y: 122, width: 391, height: 236)
    static let knobPlate = CGRect(x: 26, y: 398, width: 746, height: 150)
    static let knobCentersX: [CGFloat] = [99, 219, 339, 459, 579, 699]
    static let knobCenterY: CGFloat = 460
    static let fkeyOrigins: [CGPoint] = [CGPoint(x: 545, y: 109), CGPoint(x: 658, y: 109), CGPoint(x: 545, y: 248), CGPoint(x: 658, y: 248)]
    static let fkeySize = CGSize(width: 91, height: 115)
}

private struct DeviceBody: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Body: one dark rounded piece, like the hardware.
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [Color(hex: "#2E2E31"), Color(hex: "#18181A")], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
                .frame(width: L.device.width, height: L.device.height)
                .offset(x: L.device.minX, y: L.device.minY)
            // Screen
            RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#0C0C0D"))
                .frame(width: L.bezel.width, height: L.bezel.height)
                .offset(x: L.bezel.minX, y: L.bezel.minY)
            ScreenArea().offset(x: L.lcd.minX, y: L.lcd.minY)
            PageArrows()
            PageDashes().offset(x: L.lcd.minX, y: L.lcd.maxY + 4)
            // Function keys
            ForEach(0..<4, id: \.self) { i in
                FunctionKeyView(index: i)
                    .frame(width: L.fkeySize.width, height: L.fkeySize.height)
                    .offset(x: L.fkeyOrigins[i].x, y: L.fkeyOrigins[i].y)
            }
            // Knobs
            ForEach(0..<6, id: \.self) { i in
                KnobView(index: i)
                    .position(x: L.knobCentersX[i], y: L.knobCenterY + 10)
            }
            if ui.section == .hotkeys {
            Text("Trascina un'azione su un tasto, un tasto funzione o una manopola · Clic per modificare")
                .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                .frame(width: L.device.width)
                .offset(x: L.device.minX, y: 6)
            }
        }
        .frame(width: DeviceCanvas.design.width, height: DeviceCanvas.design.height, alignment: .topLeading)
    }
}

// MARK: - Screen

/// The LCD shows exactly what is sent to the hardware; an invisible grid on top handles editing.
private struct ScreenArea: View {
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var editor: DeckEditorModel
    @EnvironmentObject var engine: ActionEngine
    @EnvironmentObject var ui: UIState

    var body: some View {
        let cw = L.lcd.width / 5, ch = L.lcd.height / 4
        ZStack(alignment: .topLeading) {
            // Fixed background, keys sliding page by page like the iPhone home screen (and following the fingers).
            ZStack(alignment: .topLeading) {
                PanelCanvas(deck: deck, store: store, images: engine.widgetImages, touchedKey: nil, page: -1)
                if deck.swipeOffset != 0 && !deck.isInFolder {
                    let w = PanelCanvas.size.width
                    let next = deck.swipeOffset < 0
                    PanelCanvas(deck: deck, store: store, images: engine.widgetImages, touchedKey: nil,
                                page: next ? deck.neighborPages.next : deck.neighborPages.previous, drawsBackground: false)
                        .offset(x: (next ? w : -w) + deck.swipeOffset * w)
                }
                PanelCanvas(deck: deck, store: store, images: engine.widgetImages, touchedKey: nil, page: deck.currentPage, drawsBackground: false)
                    .offset(x: deck.swipeOffset * PanelCanvas.size.width)
                    .id(deck.currentPage)
                    .transition(.asymmetric(insertion: .move(edge: deck.pageForward ? .trailing : .leading),
                                            removal: .move(edge: deck.pageForward ? .leading : .trailing)))
            }
            .scaleEffect(L.lcd.width / PanelCanvas.size.width, anchor: .topLeading)
            .frame(width: L.lcd.width, height: L.lcd.height, alignment: .topLeading)
            .clipped()
            .animation(.spring(response: 0.38, dampingFraction: 0.88), value: deck.currentPage)
            .allowsHitTesting(false)
            if ui.section == .hotkeys {
                ForEach(deck.keys(onPage: deck.currentPage)) { k in
                    KeyHitArea(key: k, radius: 7).padding(1.4)
                        .frame(width: CGFloat(k.w) * cw, height: CGFloat(k.h) * ch)
                        .offset(x: CGFloat(k.x) * cw, y: CGFloat(k.y) * ch)
                }
                if let h = hover {
                    // Footprint of the dragged item: red when it would overlap other widgets.
                    let ok = h.fits
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ok ? Theme.accent.opacity(0.22) : Color.red.opacity(0.28))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ok ? Theme.accent : Color.red, lineWidth: ok ? 2 : 4))
                        .overlay { if !ok { Image(systemName: "nosign").font(.system(size: 26, weight: .bold)).foregroundStyle(Color.red) } }
                        .frame(width: CGFloat(h.w) * cw, height: CGFloat(h.h) * ch)
                        .offset(x: CGFloat(h.x) * cw, y: CGFloat(h.y) * ch)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: L.lcd.width, height: L.lcd.height, alignment: .topLeading)
        .background(Color.black)
        .onDrop(of: [.text], delegate: ScreenDropDelegate(editor: editor, cellW: cw, cellH: ch, hover: $hover))
        // A cancelled drag doesn't always report its end: clear the preview once the mouse is released.
        .onChange(of: hover != nil) { _, showing in
            guard showing else { return }
            Task { @MainActor in
                while hover != nil {
                    try? await Task.sleep(for: .milliseconds(150))
                    if NSEvent.pressedMouseButtons & 1 == 0 { hover = nil }
                }
            }
        }
    }

    @State private var hover: DropHover?
}

struct DropHover: Equatable { var x: Int; var y: Int; var w: Int; var h: Int; var fits: Bool }

/// Drop handling for the whole touch screen: the dragged item is centered on the cursor,
/// shown with its real size and refused when it overlaps other keys.
struct ScreenDropDelegate: DropDelegate {
    let editor: DeckEditorModel
    let cellW: CGFloat, cellH: CGFloat
    @Binding var hover: DropHover?

    private func target(_ info: DropInfo) -> DropHover {
        let d = editor.dragInfo ?? .init(w: 1, h: 1, ignoring: nil)
        let w = min(d.w, 5), h = min(d.h, 4)
        let x = max(0, min(5 - w, Int((info.location.x / cellW - CGFloat(w) / 2 + 0.5).rounded(.down))))
        let y = max(0, min(4 - h, Int((info.location.y / cellH - CGFloat(h) / 2 + 0.5).rounded(.down))))
        let r = DropHover(x: x, y: y, w: w, h: h, fits: editor.canPlace(x: x, y: y, w: w, h: h, slot: .touch, ignoring: d.ignoring))
        return r
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }

    func dropEntered(info: DropInfo) { if editor.dragInfo != nil { hover = target(info) } }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Updates arriving after the drop (drag info already cleared) must not show a refusal.
        guard editor.dragInfo != nil, NSEvent.pressedMouseButtons & 1 != 0 else { hover = nil; return DropProposal(operation: .copy) }
        let t = target(info)
        if t != hover { hover = t }
        return DropProposal(operation: t.fits ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) { hover = nil }

    func performDrop(info: DropInfo) -> Bool {
        let t = target(info)
        hover = nil
        guard t.fits, let provider = info.itemProviders(for: [.text]).first else { editor.dragInfo = nil; return false }
        _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let item = obj as? String else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if item.hasPrefix("key:"), let id = UUID(uuidString: String(item.dropFirst(4))) {
                        _ = editor.move(keyID: id, x: t.x, y: t.y, slot: .touch)
                    } else {
                        _ = editor.drop(actionID: item, x: t.x, y: t.y, slot: .touch)
                    }
                    editor.dragInfo = nil
                }
            }
        }
        return true
    }
}

/// Transparent interaction layer for a placed key.
struct KeyHitArea: View {
    @EnvironmentObject var editor: DeckEditorModel
    @EnvironmentObject var engine: ActionEngine
    @EnvironmentObject var deck: DeckController
    let key: KeyAssignment
    /// Corner radius of the selection ring (follows the rounded key faces).
    var radius: CGFloat = 8

    var body: some View {
        Rectangle().fill(Color.white.opacity(0.001))
            .overlay(RoundedRectangle(cornerRadius: radius + 1).strokeBorder(editor.selectedKey == key.id ? Theme.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
            // A swipe with the fingers is not a click on the key below them.
            .onTapGesture { if !deck.swipeJustHappened { editor.selectedKey = key.id; editor.selectedKnob = nil } }
            .onTapGesture(count: 2) { if !deck.swipeJustHappened { engine.press(key) } }
            .onDrag {
                editor.dragInfo = .init(w: key.w, h: key.h, ignoring: key.id)
                return NSItemProvider(object: "key:\(key.id.uuidString)" as NSString)
            } preview: {
                KeyDragPreview(key: key)
            }
            .contextMenu {
                Button("Esegui") { engine.press(key) }
                Button("Duplica") { editor.duplicate(key.id) }
                Button("Elimina", role: .destructive) { editor.delete(key.id) }
            }
            .help(ActionCatalog.descriptor(key.actionID).title)
    }
}

/// Two-finger horizontal scroll over the device moves the pages with the fingers; on release the page
/// snaps to the next / previous one (or back), like the iPhone home screen.
@MainActor
final class PageSwipeTracker {
    weak var anchor: NSView?
    private weak var deck: DeckController?
    private var pageWidth: () -> CGFloat = { 400 }
    private var monitor: Any?
    private var active = false
    private var lastDeltas: [CGFloat] = []

    func attach(deck: DeckController, pageWidth: @escaping () -> CGFloat) {
        self.deck = deck
        self.pageWidth = pageWidth
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self else { return e }
            return MainActor.assumeIsolated { self.handle(e) ? nil : e }
        }
    }

    func detach() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// True when the event was used.
    private func handle(_ e: NSEvent) -> Bool {
        guard let deck, let v = anchor, e.window === v.window, !deck.isInFolder, deck.profile.pageCount > 1 else { return false }
        // Momentum after the fingers left: ignored (the release already decided).
        if e.momentumPhase != [] { return active }
        let inside = v.bounds.contains(v.convert(e.locationInWindow, from: nil))
        if e.phase == .began {
            active = inside && abs(e.scrollingDeltaX) >= abs(e.scrollingDeltaY)
            lastDeltas = []
            if !active { return false }
        }
        guard active, e.hasPreciseScrollingDeltas else { return false }
        if e.phase == .changed || e.phase == .began {
            deck.lastSwipeActivity = Date()
            let w = max(pageWidth(), 1)
            lastDeltas = Array((lastDeltas + [e.scrollingDeltaX]).suffix(4))
            deck.swipeOffset = max(-1, min(1, deck.swipeOffset + e.scrollingDeltaX / w))
            return true
        }
        if e.phase == .ended || e.phase == .cancelled {
            active = false
            deck.lastSwipeActivity = Date()
            let velocity = lastDeltas.reduce(0, +) / CGFloat(max(lastDeltas.count, 1))
            let off = deck.swipeOffset
            let goNext = off < -0.3 || (velocity < -6 && off < 0)
            let goPrev = off > 0.3 || (velocity > 6 && off > 0)
            let target: CGFloat = goNext ? -1 : (goPrev ? 1 : 0)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { deck.swipeOffset = target } completion: { [weak deck] in
                guard let deck else { return }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) {
                    if goNext { deck.nextPage() } else if goPrev { deck.previousPage() }
                    deck.swipeOffset = 0
                }
            }
            return true
        }
        return false
    }
}

private struct SwipeAnchor: NSViewRepresentable {
    let tracker: PageSwipeTracker
    func makeNSView(context: Context) -> NSView { let v = NSView(); tracker.anchor = v; return v }
    func updateNSView(_ v: NSView, context: Context) { tracker.anchor = v }
}

/// Drag image of a key: same face, size and rounded corners as on the panel drawing.
struct KeyDragPreview: View {
    let key: KeyAssignment
    var body: some View {
        // One panel cell on the drawing ≈ 78 × 59 pt (800 × 480 panel shown 391 pt wide); keys are inset and rounded.
        let cw: CGFloat = 78.2, ch: CGFloat = 59
        WidgetOrKeyView(key: key)
            .frame(width: CGFloat(key.w) * cw - 5, height: CGFloat(key.h) * ch - 5)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            .padding(8)
    }
}

/// Empty grid slot accepting dropped actions or moved keys.
struct GridSlot: View {
    @EnvironmentObject var editor: DeckEditorModel
    let x: Int, y: Int, slot: SlotKind
    let width: CGFloat, height: CGFloat
    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(targeted ? Theme.accent.opacity(0.18) : Color.white.opacity(0.001))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? Theme.accent : .clear, lineWidth: 2))
            .overlay {
                // Editor only: a faint "+" invites to drop an action here.
                Image(systemName: "plus").font(.system(size: min(width, height) * 0.26, weight: .light))
                    .foregroundStyle(targeted ? Theme.accent : Color.white.opacity(0.22))
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first else { return false }
                if item.hasPrefix("key:"), let id = UUID(uuidString: String(item.dropFirst(4))) {
                    return editor.move(keyID: id, x: x, y: y, slot: slot)
                }
                return editor.drop(actionID: item, x: x, y: y, slot: slot)
            } isTargeted: { targeted = $0 }
    }
}

private struct PageArrows: View {
    @EnvironmentObject var deck: DeckController
    var body: some View {
        ZStack(alignment: .topLeading) {
            arrow("chevron.left") { deck.isInFolder ? deck.leaveFolder() : deck.previousPage() }.offset(x: 55, y: 222)
            arrow("chevron.right") { deck.nextPage() }.offset(x: 490, y: 222)
        }
    }
    private func arrow(_ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: s).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: "#A1A1A1")).frame(width: 20, height: 32) }
            .buttonStyle(.plain)
    }
}

private struct PageDashes: View {
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var store: ProfileStore
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<store.hotkey.pageCount, id: \.self) { p in
                Capsule().fill(!deck.isInFolder && p == deck.currentPage ? Theme.accent : Color(hex: "#3C3C3C"))
                    .frame(width: 29, height: 4.5)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture { deck.go(toPage: p) }
            }
        }
        .frame(width: L.lcd.width)
    }
}

// MARK: - Function keys

private struct FunctionKeyView: View {
    let index: Int
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState

    var body: some View {
        let x = index % 2, y = index / 2
        ZStack {
            // Physical key cap: dark, with the key's colour on its LED strip.
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(hex: "#3A3A3E"), Color(hex: "#232326")], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            if let k = deck.key(at: x, y, page: deck.currentPage, slot: .functionKey) {
                FunctionKeyCap(state: deck.state(for: k))
                if ui.section == .hotkeys { KeyHitArea(key: k, radius: 14) }
            } else if ui.section == .hotkeys {
                GridSlot(x: x, y: y, slot: .functionKey, width: L.fkeySize.width, height: L.fkeySize.height)
            }
        }
    }
}

/// Icon and label printed on a function key, with its LED strip.
private struct FunctionKeyCap: View {
    let state: KeyState
    var body: some View {
        GeometryReader { g in
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                if state.image.hasPrefix("sf:") {
                    Image(systemName: String(state.image.dropFirst(3))).font(.system(size: g.size.width * 0.24, weight: .medium))
                } else if !state.image.isEmpty {
                    KeyImage(ref: state.image, hasTitle: false).frame(width: g.size.width * 0.4, height: g.size.width * 0.4)
                }
                if !state.title.isEmpty {
                    Text(state.title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.4)
                        .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center).padding(.horizontal, 6)
                }
                Spacer(minLength: 0)
                Capsule().fill(Color(hex: state.background)).frame(width: g.size.width * 0.32, height: 4)
                    .shadow(color: Color(hex: state.background).opacity(0.9), radius: 4)
                    .padding(.bottom, 10)
            }
            .foregroundStyle(Color(hex: "#E5E5EA"))
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

// MARK: - Knobs

struct KnobView: View {
    let index: Int
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var editor: DeckEditorModel

    private var selected: Bool { ui.section == .mixer ? ui.mixerKnob == index : editor.selectedKnob == index }

    var body: some View {
        let ch = MixerChannel.allCases[index]
        let bus: MixBus = store.mixer.dualMix ? store.mixer.activeMix : .creator
        let s = store.mixer.mixes[bus]?.channels[ch] ?? ChannelState()
        let action = store.knob.knobs[index].actionID
        let ring = store.library.device.ledKnob.knobColor(index)
        VStack(spacing: 10) {
            ZStack {
                // Level ring: 270° arc, blue (red when muted).
                Circle().trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.09), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(135)).frame(width: 78, height: 78)
                Circle().trim(from: 0, to: 0.75 * CGFloat(s.level) / 100)
                    .stroke(s.muted ? Color.red : ring, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(135)).frame(width: 78, height: 78)
                    .shadow(color: (s.muted ? Color.red : ring).opacity(0.5), radius: 4)
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "#434347"), Color(hex: "#1D1D20")], center: .top, startRadius: 2, endRadius: 44))
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(0.8), radius: 3, y: 2)
                if let action {
                    Image(systemName: ActionCatalog.descriptor(action).symbol).font(.system(size: 18)).foregroundStyle(Color(hex: "#E0E0E0"))
                } else {
                    Text("\(s.level)").font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: "#E0E0E0"))
                }
            }
            .overlay(
                Circle().strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2).frame(width: 98, height: 98)
            )
            Text(action.map { ActionCatalog.descriptor($0).title.uppercased() } ?? store.mixer.name(ch))
                .font(.system(size: 9.5, weight: .regular)).tracking(1.2)
                .foregroundStyle(selected ? Theme.accent : Color(hex: "#D0D0D0"))
                .lineLimit(1).frame(width: 110)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if ui.section == .mixer { ui.mixerKnob = index } else { editor.selectedKnob = index; editor.selectedKey = nil }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first, ActionCatalog.descriptor(id).kind == .knob else { return false }
            store.knob.knobs[index].actionID = id
            editor.selectedKnob = index; editor.selectedKey = nil
            return true
        }
    }
}
