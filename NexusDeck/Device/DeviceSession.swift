import Foundation
import Combine
import AppKit

/// Connects the physical controller with the deck, audio service and action engine.
@MainActor
final class DeviceSession {
    let devices: DeviceManager
    let store: ProfileStore
    let deck: DeckController
    let audio: AudioService
    let engine: ActionEngine

    private var controller: AXController?
    private var bag = Set<AnyCancellable>()
    private var deviceBag = Set<AnyCancellable>()
    private var touchedKey: UUID?
    /// The pressed look of the touched key is shown after a short delay (not during swipes).
    private var showPressed = false
    private var pressLook: DispatchWorkItem?

    /// The touch became a swipe: release a held action and drop the press.
    private func cancelTouch() {
        pressLook?.cancel()
        if let id = touchedKey, let k = deck.keys(onPage: deck.currentPage).first(where: { $0.id == id }) {
            if k.actionID.hasPrefix("pkg:") { SDKHost.shared.keyUp(k) }
            else if ActionCatalog.holdActions.contains(k.actionID) { engine.hold(k, down: false) }
        }
        touchedKey = nil
        if showPressed { showPressed = false; redraw() }
    }
    private var touchStart: (x: Int, y: Int)?
    private var lastKnobValues = [Int](repeating: -1, count: 6)
    /// Knob reports are ignored until the saved profile has been pushed to the device.
    private var ignoreKnobsUntil = Date.distantFuture

    init(devices: DeviceManager, store: ProfileStore, deck: DeckController, audio: AudioService, engine: ActionEngine) {
        self.devices = devices
        self.store = store
        self.deck = deck
        self.audio = audio
        self.engine = engine

        devices.didConnect.sink { [weak self] hid in self?.attach(hid) }.store(in: &bag)
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("NexusDeck.firmwareDemo"), object: nil, queue: .main) { [weak self] n in
            let version = n.object as? String
            MainActor.assumeIsolated { self?.playFirmwareDemo(newVersion: version) }
        }
        #endif
        deck.$currentPage.removeDuplicates().sink { [weak self] p in
            guard let self else { return }
            let from = self.shownPage
            self.shownPage = p
            self.animatePage(from: from, to: p)
        }.store(in: &bag)
        devices.$state.sink { [weak self] s in if !s.isConnected { self?.detach() } }.store(in: &bag)
        // Live input levels on the Mixer Dashboard (only when one is on screen with its indicator on).
        // Moving the window: no panel redraws until it stops (they run on the main thread).
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowMovedAt = Date() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willMoveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowMovedAt = Date() }
        }
        audio.$meters
            .throttle(for: .milliseconds(700), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                guard let self, Date().timeIntervalSince(self.lastKnobActivity) > 1 else { return }
                if self.deck.keys(onPage: self.deck.currentPage).contains(where: { $0.actionID == ActionID.mixerDashboard && $0.settings.bool("input", true) }) {
                    self.deck.needsRedraw.send()
                }
            }
            .store(in: &bag)
        deck.needsRedraw
            .throttle(for: .milliseconds(60), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.redraw() }
            .store(in: &bag)
        // The panel can keep showing the previous frame until another one arrives: confirm the final state.
        deck.needsRedraw
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] in self?.redraw() }
            .store(in: &bag)
    }

    /// Set after the first attach: later attaches are a mixer plugged back in while NexusDeck runs.
    private var attachedBefore = false
    private let launchDate = Date()

    private func attach(_ hid: HIDDevice) {
        let c = AXController(hid: hid)
        let replug = attachedBefore
        attachedBefore = true
        // Plugged in while NexusDeck runs (not already there at launch).
        let fresh = replug || Date().timeIntervalSince(launchDate) > 3
        SDKHost.shared.debugLog("Attach (replug=\(replug))")
        lastFrame = nil
        lastSignature = nil
        // Nothing is drawn on the panel before the welcome animation.
        introUntil = .distantFuture
        ignoreKnobsUntil = .distantFuture
        controller = c
        // A fresh plug gets the audio controller only after the mixer's start-up (see below).
        if !fresh { audio.controller = c }
        deviceBag.removeAll()
        devices.inputReports.sink { c.handleInput($0) }.store(in: &deviceBag)
        c.events.receive(on: RunLoop.main).sink { [weak self] in self?.handle($0) }.store(in: &deviceBag)

        // Start-up: the mixer keeps the ring colours, but restarting the audio resets the level display
        // (config1) and every ring shows fully lit. Only the level display is restored: the colours are not
        // rewritten at start (each colour write lights its ring fully for a moment).
        audio.ringsKeepColors = true
        Task {
            // A mixer just plugged in runs its own start-up for about 10 s (it resets its LEDs at the end). Any
            // command in that window leaves it without input reports (no touch, knobs or meters) until it is
            // plugged in again. So nothing is sent until it has finished, then the start runs as at launch.
            if fresh {
                try? await Task.sleep(for: .seconds(11))
                guard controller === c else { return }
                audio.controller = c
            }
            // Strip primer: after being switched off, the mixer takes the first strip write without lighting it,
            // and the next ones start from its own blue. One write now, seconds before the LEDs come on, makes
            // the strip light straight in its colour.
            let d = store.library.device
            if let primer = audio.auraCommands(audio.auraOverride ?? d.ledAura).first { c.sendInOrder([primer]) }
            // The first reply can be lost while the device is still starting up (or busy): try a few times.
            for attempt in 0..<5 {
                if let fw = await c.firmwareVersion() { devices.updateFirmwareVersion(fw); break }
                if attempt < 4 { try? await Task.sleep(for: .milliseconds(600)) }
            }
            // Start: the logo fades in, stays a moment, then the keys appear. The first (black) frame goes out
            // before the panel is switched on, so the previous image never shows.
            let intro = PanelIntro.frames(appearing: true)
            if let black = PanelIntro.frame(0) { c.pushNow([black], interval: 0) }
            c.send(AXProtocol.panelOn())
            introUntil = Date().addingTimeInterval(Double(intro.count) * PanelIntro.interval + PanelIntro.hold + 0.3)
            Task.detached { c.pushNow(intro, interval: PanelIntro.interval) }
            c.send(AXProtocol.levelMeters(true))
            audio.applyAll()
            // Let the device apply the volumes before following the knobs again.
            try? await Task.sleep(for: .seconds(1.5))
            ignoreKnobsUntil = Date()
            // Final word on the mutes (a volume write unmutes a channel on the device).
            audio.applyMic()
            let wait = introUntil.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard controller === c else { return }
            introUntil = .distantPast
            deck.panelOn = true
            deck.deviceReady = true
            redraw()
            // The rings can stay fully lit after a quick restart even with the right volumes (the mixer drops the
            // first LED writes while it wakes up): send the ring setup and the volumes once more.
            try? await Task.sleep(for: .seconds(1))
            guard controller === c else { return }
            ignoreKnobsUntil = .distantFuture
            audio.applyMixer()
            try? await Task.sleep(for: .milliseconds(600))
            guard controller === c else { return }
            // Volumes are in place: now the rings show the levels.
            // Volumes are set: strip, function keys and rings come back together, as fast as the mixer accepts.
            audio.ringsKeepColors = false
            lastFunctionKeyColors = audio.functionKeyColors()
            audio.applyLEDs(force: true)
            SDKHost.shared.debugLog("Attach: LEDs sent")

            try? await Task.sleep(for: .seconds(1))
            guard controller === c else { return }
            ignoreKnobsUntil = Date()
            audio.applyMic()
            // Startup check: the knobs (and their rings) must match the profile; resend if the mixer missed it.
            for attempt in 0..<3 {
                try? await Task.sleep(for: .seconds(attempt == 0 ? 1 : 1.5))
                guard controller === c else { return }
                if await audio.verifyDeviceState() { break }
                SDKHost.shared.debugLog("Startup check: mixer out of sync, sending the profile again (\(attempt + 1))")
                ignoreKnobsUntil = .distantFuture
                audio.applyAll()
                try? await Task.sleep(for: .seconds(1.5))
                ignoreKnobsUntil = Date()
                audio.applyMic()
            }
        }
    }

    /// Turns the panel off when NexusDeck quits, as the reference app does.
    /// Quit: the logo fades out on the panel, then the panel turns off.
    func shutdown() {
        guard let c = controller else { return }
        if deck.panelOn, let logo = PanelIntro.frame(1) {
            // Logo at once, a pause, then it fades out.
            c.pushNow([logo], interval: 0)
            Thread.sleep(forTimeInterval: PanelIntro.hold)
            c.pushNow(PanelIntro.frames(appearing: false), interval: PanelIntro.interval)
        }
        audio.allLEDsOff()
        c.sendAndWait(AXProtocol.panelOff())
    }

    private func detach() {
        if controller != nil { SDKHost.shared.debugLog("Detach") }
        deck.deviceReady = false
        audio.ledTask?.cancel()
        introUntil = .distantPast
        controller = nil
        audio.controller = nil
        deviceBag.removeAll()
    }

    private var lastFunctionKeyColors: [String?]?
    private var lastFunctionKeys: UInt8 = 0
    private var lastKnobPress: UInt8 = 0
    private var lastFrame: Data?
    private var redrawDeferred = false
    private var lastPush = Date.distantPast
    private var finalFrame: DispatchWorkItem?
    /// While a knob turns, live meters do not redraw the panel (the mixer handles knobs late when busy).
    private var lastKnobActivity = Date.distantPast

    // MARK: Page animation (experimental)

    private var shownPage = 0
    /// While the page slide is being sent, normal redraws wait (they would replace the queued frames).
    private var animatingUntil = Date.distantPast
    private var pageAnimation: Task<Void, Never>?
    private var lastPageAnimation = Date.distantPast

    /// Sends a few light frames of the old page sliding out and the new one sliding in, then the final page.
    private func animatePage(from: Int, to: Int) {
        guard store.library.device.pageAnimation, deck.panelOn, from != to, let c = controller else { return }
        let forward = deck.pageForward
        animatingUntil = Date().addingTimeInterval(1.5)
        pageAnimation?.cancel()
        // Swiping fast: skip the slide (it would only pile up frames) and show the page.
        if Date().timeIntervalSince(lastPageAnimation) < 0.6 {
            lastPageAnimation = Date()
            animatingUntil = .distantPast
            lastSignature = nil
            redraw()
            return
        }
        lastPageAnimation = Date()
        // Three pictures drawn once (background, old page, new page); the slide frames are composed from them
        // with Core Graphics off the main thread (much lighter than drawing every frame with SwiftUI).
        let images = engine.widgetImages
        guard let bg = PanelRenderer.layer(deck: deck, store: store, images: images, page: -1, background: true),
              let old = PanelRenderer.layer(deck: deck, store: store, images: images, page: from, background: false),
              let new = PanelRenderer.layer(deck: deck, store: store, images: images, page: to, background: false),
              let finalImage = PanelRenderer.image(deck: deck, store: store, images: images, touched: nil) else {
            animatingUntil = .distantPast; return
        }
        pageAnimation = Task { @MainActor in
            let frames: [Data] = await Task.detached(priority: .userInitiated) {
                var out: [Data] = []
                for t: CGFloat in [0.2, 0.45, 0.7, 0.88] {
                    let p = 1 - pow(1 - t, 2)
                    if let f = PanelRenderer.slide(bg: bg, old: old, new: new, forward: forward, progress: p),
                       let j = PanelRenderer.encode(f, quality: 0.3) { out.append(j) }
                }
                if let j = PanelRenderer.encode(finalImage, quality: 0.8) { out.append(j) }
                return out
            }.value
            if Task.isCancelled { return }
            for f in frames.dropLast() { c.append(jpeg: f) }
            if let final = frames.last {
                lastFrame = final
                lastPush = Date()
                c.append(jpeg: final)
            }
            animatingUntil = .distantPast
        }
    }

    /// While the start logo is playing, the panel is not redrawn.
    private var introUntil = Date.distantPast

    /// Firmware update screen with a progress bar (demo: 0 → 100 % in about 6 s, then back to the keys).
    /// Test: the firmware update was simulated in this session (the settings hide the button).
    static var firmwareTestDone = false

    func playFirmwareDemo(newVersion: String? = nil) {
        guard let c = controller else { return }
        let steps = (0...24).map { CGFloat($0) / 24 }
        let frames = steps.compactMap { PanelIntro.updateFrame($0) } + [PanelIntro.updateFrame(1)].compactMap { $0 }
        introUntil = Date().addingTimeInterval(Double(frames.count) * 0.25 + 1.2)
        Task.detached {
            c.pushNow(frames, interval: 0.25)
            Thread.sleep(forTimeInterval: 1)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.introUntil = .distantPast; self.lastFrame = nil; self.lastSignature = nil; self.redraw()
                // Simulated update: the new version is shown (until the app restarts and reads the real one).
                if let newVersion {
                    DeviceSession.firmwareTestDone = true
                    self.devices.updateFirmwareVersion(newVersion)
                }
            }
        }
    }

    private var windowMovedAt = Date.distantPast
    private var lastSignature: Int?
    private var frameGeneration = 0
    private let encodeQueue = DispatchQueue(label: "nexusdeck.panel.encode", qos: .userInitiated)

    /// Hash of everything the panel image depends on.
    private func panelSignature(turning: Bool) -> Int {
        var h = Hasher()
        let keys = deck.keys(onPage: deck.currentPage)
        h.combine(keys)
        h.combine(deck.currentPage)
        h.combine(deck.panelOn)
        h.combine(turning)
        h.combine(showPressed ? touchedKey : nil)
        for k in keys {
            h.combine(deck.stateIndex[k.id])
            h.combine(deck.liveText[k.id])
            if let img = engine.widgetImages[k.id] { h.combine(ObjectIdentifier(img)) }
            if k.actionID == ActionID.mixerDashboard {
                h.combine(store.mixer)
                // Live input rings: steps of 1/8, so tiny level changes do not cost a new frame.
                if k.settings.bool("input", true) {
                    for b in MixBus.allCases { for ch in MixerChannel.allCases { h.combine((LevelMeters.shared.values[b]?[ch] ?? 0) / 12) } }
                }
            }
            if k.actionID == ActionID.volume || k.actionID == ActionID.pageIndicator { h.combine(store.mixer); h.combine(store.hotkey.pageCount) }
        }
        let d = store.library.device
        h.combine(d.background)
        h.combine(d.panelOpacity)
        h.combine(d.autoHideGrid)
        h.combine(d.ledKnob)
        return h.finalize()
    }

    func redraw() {
        guard let c = controller, Date() >= introUntil else { return }
        if Date().timeIntervalSince(windowMovedAt) < 0.35 {
            if !redrawDeferred {
                redrawDeferred = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.redrawDeferred = false; self?.redraw() }
            }
            return
        }
        // A touch on the panel wins over the page slide still being sent (the press must show at once).
        if touchStart != nil || showPressed { animatingUntil = .distantPast; pageAnimation?.cancel() }
        if Date() < animatingUntil {
            if !redrawDeferred {
                redrawDeferred = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.redrawDeferred = false; self?.redraw() }
            }
            return
        }
        // While a knob turns: light frames (lower JPEG quality), at most one every 150 ms, so the mixer
        // still follows the knob at once. The final frame after the turn is drawn at full quality.
        let turning = Date().timeIntervalSince(lastKnobActivity) < 0.35
        if turning && Date().timeIntervalSince(lastPush) < 0.15 {
            if !redrawDeferred {
                redrawDeferred = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.redrawDeferred = false; self?.redraw() }
            }
            return
        }
        // Function keys are physical buttons: their LEDs follow the keys assigned on this page.
        let colors = audio.functionKeyColors()
        if colors != lastFunctionKeyColors {
            lastFunctionKeyColors = colors
            Task { await audio.sendFunctionKeyLEDs() }
        }
        // Cheap check before the (expensive) render: nothing drawn on the panel changed → nothing to do.
        let signature = panelSignature(turning: turning)
        if signature == lastSignature { return }
        lastSignature = signature
        // Drawn here (SwiftUI), compressed off the main thread, sent in order.
        guard let cg = PanelRenderer.image(deck: deck, store: store, images: engine.widgetImages, touched: showPressed ? touchedKey : nil) else { return }
        let quality: CGFloat = turning ? 0.45 : 0.8
        let generation = frameGeneration &+ 1
        frameGeneration = generation
        lastPush = Date()
        encodeQueue.async { [weak self] in
            guard let jpeg = PanelRenderer.encode(cg, quality: quality) else { return }
            DispatchQueue.main.async {
                guard let self, self.frameGeneration == generation, self.controller === c else { return }
                // An unchanged frame is not sent again: every frame keeps the mixer busy (and slows its knobs).
                guard jpeg != self.lastFrame else { return }
                self.lastFrame = jpeg
                c.push(jpeg: jpeg)
            }
        }
    }

    // MARK: Events

    private func handle(_ e: AXProtocol.Event) {
        switch e {
        case .touch(let x, let y):
            if !deck.panelOn { engine.setPanel(on: true); return }
            if let start = touchStart {
                // The finger moved: it is a swipe, not a press (no pressed look, no action on release).
                if touchedKey != nil, abs(x - start.0) > 28 || abs(y - start.1) > 28 { cancelTouch() }
                return
            }
            touchStart = (x, y)
            let cx = min(4, x * 5 / AXProtocol.panelWidth), cy = min(3, y * 4 / AXProtocol.panelHeight)
            touchedKey = deck.key(at: cx, cy)?.id
            if let k = deck.key(at: cx, cy) {
                if k.actionID.hasPrefix("pkg:") { SDKHost.shared.keyDown(k) }
                else if ActionCatalog.holdActions.contains(k.actionID) { engine.hold(k, down: true) }
            }
            // The pressed look appears only if the finger stays put for a moment (a swipe starting on a key
            // must not look like a press).
            pressLook?.cancel()
            let w = DispatchWorkItem { [weak self] in
                guard let self, self.touchedKey != nil else { return }
                self.showPressed = true
                self.redraw()
            }
            pressLook = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: w)
        case .touchUp:
            pressLook?.cancel()
            defer { touchStart = nil; touchedKey = nil; showPressed = false; redraw() }
            guard let id = touchedKey, let key = deck.keys(onPage: deck.currentPage).first(where: { $0.id == id }) else { return }
            if key.actionID == ActionID.mixerDashboard { audio.switchActiveMix(); engine.syncStates(); deck.needsRedraw.send(); return }
            if key.actionID.hasPrefix("pkg:") { SDKHost.shared.keyUp(key); return }
            if ActionCatalog.holdActions.contains(key.actionID) { engine.hold(key, down: false); return }
            engine.press(key)
        case .gesture(let g):
            cancelTouch()
            switch g {
            case .left: deck.nextPage()
            case .right: deck.previousPage()
            case .up, .down: break
            }
        case .functionKeys(let mask):
            let previous = lastFunctionKeys
            lastFunctionKeys = mask
            for i in 0..<4 {
                let bit: UInt8 = 1 << i
                guard let key = deck.key(at: i % 2, i / 2, page: deck.currentPage, slot: .functionKey) else { continue }
                let holds = ActionCatalog.holdActions.contains(key.actionID)
                if mask & bit != 0, previous & bit == 0 {
                    if key.actionID.hasPrefix("pkg:") { SDKHost.shared.keyDown(key) }
                    else if holds { engine.hold(key, down: true) }
                    else { engine.press(key) }
                } else if mask & bit == 0, previous & bit != 0 {
                    if key.actionID.hasPrefix("pkg:") { SDKHost.shared.keyUp(key) }
                    else if holds { engine.hold(key, down: false) }
                }
            }
        case .knobValue(let i, let v, let muted):
            lastKnobActivity = Date()
            finalFrame?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.redraw() }
            finalFrame = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
            let prev = lastKnobValues[i]
            lastKnobValues[i] = v
            guard Date() >= ignoreKnobsUntil else { return }
            if store.knob.knobs[i].actionID != nil {
                if prev >= 0, v != prev { _ = engine.knobTurned(i, delta: v > prev ? 1 : -1) }
                // Keep the hardware channel where it was.
                let lvl = store.mixer.mixes[store.mixer.activeMix]?.channels[MixerChannel.allCases[i]]?.level ?? 50
                controller?.send(AXProtocol.mixerVolume(mixer: store.mixer.activeMix.rawValue, channel: i, value: AudioService.hw(lvl)))
            } else {
                audio.knobMoved(i, hwValue: v)
                // Turning a knob writes its volume on the device, which unmutes it: keep the mutes we set.
                // Only when needed: every mute write while turning makes the mixer follow the knob late.
                if i != 0, audio.hasMuteBit(channel: i) {
                    audio.reassertMutes()
                }
                _ = muted // The report bit does not reflect the mute state: it is read from the mixer on release.
            }
            engine.syncStates()
        case .knobPress(let mask):
            // A press of a mixer-channel knob toggles its mute (the firmware does it too, but for the Mic
            // only in the Audience mix): toggle on release and send the masks so both mixes agree.
            if mask == 0 {
                for i in 0..<6 where lastKnobPress & (1 << i) != 0 && store.knob.knobs[i].actionID == nil {
                    audio.knobToggledMute(i)
                }
                engine.syncStates()
                deck.needsRedraw.send()
            }
            lastKnobPress = mask
            // Mixer-channel knobs mute in hardware; only custom knob actions are handled here.
            for i in 0..<6 where mask & (1 << i) != 0 && store.knob.knobs[i].actionID != nil { engine.knobPressed(i) }
            engine.syncStates()
        case .levels(let l):
            audio.updateMeters(l)
        case .renderAck:
            break
        }
    }
}
