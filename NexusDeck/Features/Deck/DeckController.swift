import SwiftUI
import Combine

/// Runtime state of the panel: current page, folder navigation and per-key dynamic state.
@MainActor
final class DeckController: ObservableObject {
    @Published var currentPage = 0
    /// Direction of the last page change (for the slide animation of the panel drawing).
    @Published private(set) var pageForward = true
    /// Live trackpad swipe on the panel drawing, in page widths (-1 … 1, negative = towards the next page).
    @Published var swipeOffset: CGFloat = 0
    /// Last moment a trackpad swipe moved the pages: taps just after it are not clicks on a key.
    var lastSwipeActivity = Date.distantPast
    var swipeJustHappened: Bool { swipeOffset != 0 || Date().timeIntervalSince(lastSwipeActivity) < 0.4 }

    /// Pages next to the current one (wrapping, like the arrows), for the swipe preview.
    var neighborPages: (previous: Int, next: Int) {
        let n = max(profile.pageCount, 1)
        return ((currentPage - 1 + n) % n, (currentPage + 1) % n)
    }
    /// Page to return to when leaving a folder.
    @Published private(set) var pageStack: [Int] = []
    /// Current visual state index for multi-state keys.
    @Published var stateIndex: [UUID: Int] = [:]
    /// Live text drawn on top of keys (counters, CPU, etc.).
    @Published var liveText: [UUID: String] = [:]
    @Published var panelOn = true
    /// The connected mixer has received the profile (end of the start-up sequence).
    @Published var deviceReady = false

    /// Bumped whenever the device needs a repaint.
    let needsRedraw = PassthroughSubject<Void, Never>()

    unowned let store: ProfileStore

    init(store: ProfileStore) {
        self.store = store
    }

    var profile: HotkeyProfile { store.hotkey }

    /// Function keys are physical buttons: one fixed set for the whole profile (stored on page 0),
    /// as in the reference app. They do not change with the page.
    func keys(onPage page: Int, slot: SlotKind = .touch) -> [KeyAssignment] {
        let p = slot == .functionKey ? 0 : page
        return profile.keys.filter { $0.page == p && $0.slot == slot }
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

    /// `forward` overrides the direction (the arrows wrap around: from the first page "back" is the last one).
    func go(toPage page: Int, forward: Bool? = nil) {
        let maxPage = max(profile.pageCount - 1, 0)
        let p = min(max(page, 0), maxPage)
        pageStack.removeAll()
        // The direction is set before the page, which is what the animations observe.
        if currentPage != p { pageForward = forward ?? (p > currentPage); currentPage = p; needsRedraw.send() }
    }

    func nextPage() {
        guard !isInFolder else { return }
        let p = (currentPage + 1) % max(profile.pageCount, 1)
        go(toPage: p, forward: true)
    }
    func previousPage() {
        guard !isInFolder else { return }
        let p = (currentPage - 1 + profile.pageCount) % max(profile.pageCount, 1)
        go(toPage: p, forward: false)
    }

    func enterFolder(_ page: Int) {
        pageStack.append(currentPage)
        pageForward = true
        currentPage = page
        needsRedraw.send()
    }

    func leaveFolder() {
        pageForward = false
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
