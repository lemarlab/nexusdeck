import SwiftUI
import Combine

/// Runtime state of the panel: current page, folder navigation and per-key dynamic state.
@MainActor
final class DeckController: ObservableObject {
    @Published var currentPage = 0
    /// Page to return to when leaving a folder.
    @Published private(set) var pageStack: [Int] = []
    /// Current visual state index for multi-state keys.
    @Published var stateIndex: [UUID: Int] = [:]
    /// Live text drawn on top of keys (counters, CPU, etc.).
    @Published var liveText: [UUID: String] = [:]
    @Published var panelOn = true

    /// Bumped whenever the device needs a repaint.
    let needsRedraw = PassthroughSubject<Void, Never>()

    unowned let store: ProfileStore

    init(store: ProfileStore) {
        self.store = store
    }

    var profile: HotkeyProfile { store.hotkey }

    func keys(onPage page: Int, slot: SlotKind = .touch) -> [KeyAssignment] {
        profile.keys.filter { $0.page == page && $0.slot == slot }
    }

    func key(at x: Int, _ y: Int, page: Int? = nil, slot: SlotKind = .touch) -> KeyAssignment? {
        keys(onPage: page ?? currentPage, slot: slot).first { $0.covers(x: x, y: y) }
    }

    func state(for key: KeyAssignment) -> KeyState {
        let i = stateIndex[key.id] ?? 0
        return key.states.indices.contains(i) ? key.states[i] : (key.states.first ?? KeyState())
    }

    func setState(_ key: UUID, _ index: Int) {
        guard stateIndex[key] != index else { return }
        stateIndex[key] = index
        needsRedraw.send()
    }

    func setLiveText(_ key: UUID, _ text: String?) {
        guard liveText[key] != text else { return }
        liveText[key] = text
        needsRedraw.send()
    }

    /// Setting state for every key of an action type (e.g. OBS record state).
    func setState(forAction actionID: String, where predicate: (KeyAssignment) -> Bool = { _ in true }, _ index: Int) {
        for k in profile.keys + profile.keys.flatMap(\.children) where k.actionID == actionID && predicate(k) {
            setState(k.id, index)
        }
    }

    // MARK: Navigation

    var isInFolder: Bool { currentPage >= PageID.groupBase }

    func go(toPage page: Int) {
        let maxPage = max(profile.pageCount - 1, 0)
        let p = min(max(page, 0), maxPage)
        pageStack.removeAll()
        if currentPage != p { currentPage = p; needsRedraw.send() }
    }

    func nextPage() { if !isInFolder { go(toPage: (currentPage + 1) % max(profile.pageCount, 1)) } }
    func previousPage() { if !isInFolder { go(toPage: (currentPage - 1 + profile.pageCount) % max(profile.pageCount, 1)) } }

    func enterFolder(_ page: Int) {
        pageStack.append(currentPage)
        currentPage = page
        needsRedraw.send()
    }

    func leaveFolder() {
        currentPage = pageStack.popLast() ?? 0
        needsRedraw.send()
    }

    func profileChanged() {
        stateIndex.removeAll()
        liveText.removeAll()
        pageStack.removeAll()
        currentPage = 0
        needsRedraw.send()
    }
}
