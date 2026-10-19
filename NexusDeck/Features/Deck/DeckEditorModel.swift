import SwiftUI

@MainActor
final class DeckEditorModel: ObservableObject {
    @Published var selectedKey: UUID?
    @Published var selectedKnob: Int?
    @Published var message: String?

    /// Size of what is being dragged (new action or existing key), for the drop preview.
    struct DragInfo: Equatable { var w: Int; var h: Int; var ignoring: UUID? }
    @Published var dragInfo: DragInfo?

    /// Whether a w×h item fits at x,y on the current page without overlapping other keys.
    func canPlace(x: Int, y: Int, w: Int, h: Int, slot: SlotKind, ignoring: UUID? = nil) -> Bool {
        fits(x: x, y: y, w: w, h: h, page: deck.currentPage, slot: slot, ignoring: ignoring)
    }

    let store: ProfileStore
    let deck: DeckController

    init(store: ProfileStore, deck: DeckController) {
        self.store = store
        self.deck = deck
    }

    var columns: Int { 5 }
    var rows: Int { 4 }

    // MARK: Placement

    private func fits(x: Int, y: Int, w: Int, h: Int, page: Int, slot: SlotKind, ignoring: UUID? = nil) -> Bool {
        let maxX = slot == .touch ? columns : 2
        let maxY = slot == .touch ? rows : 2
        guard x >= 0, y >= 0, x + w <= maxX, y + h <= maxY else { return false }
        for k in store.hotkey.keys where k.page == page && k.slot == slot && k.id != ignoring {
            let overlap = x < k.x + k.w && k.x < x + w && y < k.y + k.h && k.y < y + h
            if overlap { return false }
        }
        return true
    }

    func drop(actionID: String, x: Int, y: Int, slot: SlotKind) -> Bool {
        let d = ActionCatalog.descriptor(actionID)
        guard d.kind != .knob else { message = "Le azioni manopola si assegnano alle manopole."; return false }
        guard !d.onlyMultiAction else { message = "Questa azione si usa solo dentro una multi-azione."; return false }
        let w = slot == .touch ? d.width : 1, h = slot == .touch ? d.height : 1
        if slot == .functionKey, d.kind == .widget { message = "I widget non possono stare sui tasti funzione."; return false }
        let page = deck.currentPage
        guard fits(x: x, y: y, w: w, h: h, page: page, slot: slot) else { message = "Spazio insufficiente in questa posizione."; return false }
        var key = KeyAssignment(actionID: actionID, slot: slot, page: page, x: x, y: y, w: w, h: h, states: ActionCatalog.defaultStates(for: d))
        if actionID == ActionID.group {
            store.hotkey.groupCounter += 1
            let gp = PageID.groupBase + store.hotkey.groupCounter
            key.settings["groupPage"] = .number(Double(gp))
            store.hotkey.keys.append(KeyAssignment(actionID: ActionID.groupBack, page: gp, x: 0, y: 0, states: ActionCatalog.defaultStates(for: ActionCatalog.descriptor(ActionID.groupBack))))
        }
        if actionID == ActionID.pageSwitch { key.settings["page"] = .number(0) }
        store.hotkey.keys.append(key)
        selectedKey = key.id
        deck.needsRedraw.send()
        return true
    }

    /// Changes the size of a placed widget if the new size fits where it is.
    func resize(_ id: UUID, w: Int, h: Int) -> Bool {
        guard let i = store.hotkey.keys.firstIndex(where: { $0.id == id }) else { return false }
        let k = store.hotkey.keys[i]
        guard fits(x: k.x, y: k.y, w: w, h: h, page: k.page, slot: k.slot, ignoring: k.id) else { return false }
        store.hotkey.keys[i].w = w
        store.hotkey.keys[i].h = h
        deck.needsRedraw.send()
        return true
    }

    func move(keyID: UUID, x: Int, y: Int, slot: SlotKind) -> Bool {
        guard let i = store.hotkey.keys.firstIndex(where: { $0.id == keyID }) else { return false }
        let k = store.hotkey.keys[i]
        if k.slot != slot, k.w > 1 || k.h > 1 { return false }
        let page = deck.currentPage
        guard fits(x: x, y: y, w: k.w, h: k.h, page: page, slot: slot, ignoring: k.id) else { message = "Spazio insufficiente in questa posizione."; return false }
        store.hotkey.keys[i].x = x
        store.hotkey.keys[i].y = y
        store.hotkey.keys[i].page = page
        store.hotkey.keys[i].slot = slot
        deck.needsRedraw.send()
        return true
    }

    func delete(_ id: UUID) {
        guard let k = store.hotkey.keys.first(where: { $0.id == id }) else { return }
        if k.actionID == ActionID.groupBack { message = "Il tasto Indietro di una cartella non può essere rimosso."; return }
        if k.actionID == ActionID.group, let gp = k.settings["groupPage"]?.int {
            store.hotkey.keys.removeAll { $0.page == gp }
        }
        store.hotkey.keys.removeAll { $0.id == id }
        if selectedKey == id { selectedKey = nil }
        deck.needsRedraw.send()
    }

    func duplicate(_ id: UUID) {
        guard var k = store.hotkey.keys.first(where: { $0.id == id }), k.actionID != ActionID.group else { return }
        for y in 0..<rows { for x in 0..<columns where fits(x: x, y: y, w: k.w, h: k.h, page: deck.currentPage, slot: .touch) {
            k.id = UUID(); k.x = x; k.y = y; k.page = deck.currentPage; k.slot = .touch
            store.hotkey.keys.append(k); selectedKey = k.id; deck.needsRedraw.send(); return
        } }
        message = "Nessuno slot libero in questa pagina."
    }

    func binding(for id: UUID) -> Binding<KeyAssignment>? {
        guard store.hotkey.keys.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.store.hotkey.keys.first { $0.id == id } ?? KeyAssignment(actionID: "") },
            set: { newValue in
                if let i = self.store.hotkey.keys.firstIndex(where: { $0.id == id }) {
                    self.store.hotkey.keys[i] = newValue
                    self.deck.needsRedraw.send()
                }
            })
    }

    // MARK: Pages

    func addPage() {
        guard store.hotkey.pageCount < 10 else { message = "Massimo 10 pagine."; return }
        store.hotkey.pageCount += 1
        deck.go(toPage: store.hotkey.pageCount - 1)
    }

    func removeCurrentPage() {
        let p = deck.currentPage
        guard !deck.isInFolder, store.hotkey.pageCount > 1 else { return }
        store.hotkey.keys.removeAll { $0.page == p && $0.slot == .touch }
        for i in store.hotkey.keys.indices where store.hotkey.keys[i].slot == .touch && store.hotkey.keys[i].page > p && store.hotkey.keys[i].page < PageID.groupBase {
            store.hotkey.keys[i].page -= 1
        }
        store.hotkey.pageCount -= 1
        deck.go(toPage: min(p, store.hotkey.pageCount - 1))
    }

    // MARK: Profiles

    func newProfile() {
        var p = HotkeyProfile(title: "Nuovo profilo")
        p.pageCount = 1
        store.library.hotkeyProfiles.append(p)
        activate(p.id)
    }

    func duplicateProfile() {
        var p = store.hotkey
        p.id = UUID()
        p.title += " (copia)"
        store.library.hotkeyProfiles.append(p)
        activate(p.id)
    }

    func deleteProfile() {
        guard store.library.hotkeyProfiles.count > 1 else { message = "Deve esistere almeno un profilo."; return }
        let id = store.hotkey.id
        store.library.hotkeyProfiles.removeAll { $0.id == id }
        activate(store.library.hotkeyProfiles[0].id)
    }

    func activate(_ id: UUID) {
        store.library.activeHotkeyProfile = id
        selectedKey = nil
        deck.profileChanged()
    }
}
