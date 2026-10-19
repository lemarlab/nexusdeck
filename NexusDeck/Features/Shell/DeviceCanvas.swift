import SwiftUI

/// Interactive illustration of the controller (layout measured from the reference, in points).
struct DeviceCanvas: View {
    static let design = CGSize(width: 803, height: 599)

    var body: some View {
        GeometryReader { g in
            let scale = min(g.size.width / Self.design.width, g.size.height / Self.design.height)
            DeviceBody()
                .frame(width: Self.design.width, height: Self.design.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: g.size.width, height: g.size.height)
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
            // Body
            RoundedRectangle(cornerRadius: 22).fill(Theme.deviceBody)
                .frame(width: L.device.width, height: L.device.height)
                .offset(x: L.device.minX, y: L.device.minY)
            // Plates
            // Screen and key plates as one piece: rounded outer corners, concave fillets where they join.
            Path { p in
                let s = L.screenPlate, k = L.keyPlate
                p.move(to: CGPoint(x: s.minX, y: s.minY))
                p.addArc(tangent1End: CGPoint(x: s.maxX, y: s.minY), tangent2End: CGPoint(x: s.maxX, y: k.minY), radius: 10)
                p.addArc(tangent1End: CGPoint(x: s.maxX, y: k.minY), tangent2End: CGPoint(x: k.maxX, y: k.minY), radius: 10)
                p.addLine(to: CGPoint(x: k.maxX, y: k.minY))
                p.addLine(to: CGPoint(x: k.maxX, y: k.maxY))
                p.addArc(tangent1End: CGPoint(x: s.maxX, y: k.maxY), tangent2End: CGPoint(x: s.maxX, y: s.maxY), radius: 10)
                p.addArc(tangent1End: CGPoint(x: s.maxX, y: s.maxY), tangent2End: CGPoint(x: s.minX, y: s.maxY), radius: 10)
                p.addLine(to: CGPoint(x: s.minX, y: s.maxY))
                p.closeSubpath()
            }
            .fill(Theme.devicePlate)
            if ui.section == .mixer {
                // Down to the bottom of the body, following its rounded corners.
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 0)
                    .fill(Theme.devicePlate)
                    .frame(width: L.knobPlate.width, height: L.knobPlate.height)
                    .offset(x: L.knobPlate.minX, y: L.knobPlate.minY)
                Rectangle().fill(Theme.accent).frame(width: 3, height: L.knobPlate.height - 22).offset(x: L.knobPlate.minX, y: L.knobPlate.minY)
                Rectangle().fill(Theme.accent).frame(width: 3, height: L.knobPlate.height - 22).offset(x: L.knobPlate.maxX - 3, y: L.knobPlate.minY)
            } else {
                Rectangle().fill(Theme.accent).frame(width: 3, height: L.screenPlate.height).offset(x: L.screenPlate.minX, y: L.screenPlate.minY)
                Rectangle().fill(Theme.accent).frame(width: 3, height: L.keyPlate.height).offset(x: L.keyPlate.maxX - 3, y: L.keyPlate.minY)
            }
            // Labels
            Text("NEXUSDECK").font(.system(size: 13.5, weight: .heavy)).tracking(1.2).foregroundStyle(Color(hex: "#D9D9D9"))
                .offset(x: 87, y: 54)
            BrandMark(size: 26).offset(x: 575, y: 58)
            // Screen
            RoundedRectangle(cornerRadius: 7).fill(Theme.bezel)
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
            // Mix label
            VStack(spacing: 8) {
                Text(store.mixer.dualMix ? store.mixer.activeMix.title : "Master Mix")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textMid)
                if store.mixer.dualMix {
                    HStack(spacing: 6) {
                        ForEach(MixBus.allCases) { b in
                            Capsule().fill(store.mixer.activeMix == b ? Theme.accent : Color(hex: "#3C3C3C")).frame(width: 30, height: 4)
                        }
                    }
                }
            }
            .frame(width: L.device.width)
            .offset(x: L.device.minX, y: 563)
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
            PanelCanvas(deck: deck, store: store, images: engine.widgetImages, touchedKey: nil)
                .scaleEffect(L.lcd.width / PanelCanvas.size.width, anchor: .topLeading)
                .frame(width: L.lcd.width, height: L.lcd.height, alignment: .topLeading)
                .clipped()
                .allowsHitTesting(false)
            if ui.section == .hotkeys {
                ForEach(deck.keys(onPage: deck.currentPage)) { k in
                    KeyHitArea(key: k)
                        .frame(width: CGFloat(k.w) * cw, height: CGFloat(k.h) * ch)
                        .offset(x: CGFloat(k.x) * cw, y: CGFloat(k.y) * ch)
                }
                if let h = hover {
                    // Footprint of the dragged item: red when it would overlap other widgets.
                    let ok = h.fits
                    Rectangle()
                        .fill(ok ? Theme.accent.opacity(0.22) : Color.red.opacity(0.28))
                        .overlay(Rectangle().strokeBorder(ok ? Theme.accent : Color.red, lineWidth: ok ? 2 : 4))
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
    let key: KeyAssignment

    var body: some View {
        Rectangle().fill(Color.white.opacity(0.001))
            .overlay(Rectangle().strokeBorder(editor.selectedKey == key.id ? Theme.accent : .clear, lineWidth: 2).padding(2))
            .contentShape(Rectangle())
            .onTapGesture { editor.selectedKey = key.id; editor.selectedKnob = nil }
            .onTapGesture(count: 2) { engine.press(key) }
            .onDrag {
                editor.dragInfo = .init(w: key.w, h: key.h, ignoring: key.id)
                return NSItemProvider(object: "key:\(key.id.uuidString)" as NSString)
            } preview: {
                WidgetOrKeyView(key: key).frame(width: 75 * CGFloat(key.w), height: 54 * CGFloat(key.h))
            }
            .contextMenu {
                Button("Esegui") { engine.press(key) }
                Button("Duplica") { editor.duplicate(key.id) }
                Button("Elimina", role: .destructive) { editor.delete(key.id) }
            }
            .help(ActionCatalog.descriptor(key.actionID).title)
    }
}

/// Empty grid slot accepting dropped actions or moved keys.
struct GridSlot: View {
    @EnvironmentObject var editor: DeckEditorModel
    let x: Int, y: Int, slot: SlotKind
    let width: CGFloat, height: CGFloat
    @State private var targeted = false

    var body: some View {
        Rectangle()
            .fill(targeted ? Theme.accent.opacity(0.18) : Color.white.opacity(0.001))
            .overlay(Rectangle().strokeBorder(targeted ? Theme.accent : .clear, lineWidth: 2))
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
            RoundedRectangle(cornerRadius: 5).fill(Color.black)
            if let k = deck.key(at: x, y, page: deck.currentPage, slot: .functionKey) {
                WidgetOrKeyView(key: k).clipShape(RoundedRectangle(cornerRadius: 5))
                if ui.section == .hotkeys { KeyHitArea(key: k) }
            } else if ui.section == .hotkeys {
                GridSlot(x: x, y: y, slot: .functionKey, width: L.fkeySize.width, height: L.fkeySize.height)
            }
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
        VStack(spacing: 10) {
            ZStack {
                // Outer bezel
                Circle().fill(Color(hex: "#141414")).frame(width: 90, height: 90)
                // Ring segments: 270° sweep
                ForEach(0..<20, id: \.self) { seg in
                    let lit = Double(seg) < Double(s.level) / 5
                    Capsule()
                        .fill(s.muted ? Color.red.opacity(lit ? 0.9 : 0.15) : (lit ? Theme.knobBlue : Color.black.opacity(0.9)))
                        .frame(width: 3.5, height: 9)
                        .offset(y: -37)
                        .rotationEffect(.degrees(-135 + Double(seg) * 270 / 19))
                }
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "#3A3A3A"), Color(hex: "#262626")], center: .top, startRadius: 2, endRadius: 40))
                    .frame(width: 56, height: 56)
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
