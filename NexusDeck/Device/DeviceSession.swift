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
        devices.$state.sink { [weak self] s in if !s.isConnected { self?.detach() } }.store(in: &bag)
        // Live input levels on the Mixer Dashboard (only when one is on screen with its indicator on).
        audio.$meters
            .throttle(for: .milliseconds(400), scheduler: RunLoop.main, latest: true)
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

    private func attach(_ hid: HIDDevice) {
        let c = AXController(hid: hid)
        lastFrame = nil
        ignoreKnobsUntil = .distantFuture
        controller = c
        audio.controller = c
        deviceBag.removeAll()
        devices.inputReports.sink { c.handleInput($0) }.store(in: &deviceBag)
        c.events.receive(on: RunLoop.main).sink { [weak self] in self?.handle($0) }.store(in: &deviceBag)

        Task {
            if let fw = await c.firmwareVersion() { devices.updateFirmwareVersion(fw) }
            c.send(AXProtocol.panelOn())
            c.send(AXProtocol.levelMeters(true))
            audio.applyAll()
            // Let the device apply the volumes before following the knobs again.
            try? await Task.sleep(for: .seconds(1.5))
            ignoreKnobsUntil = Date()
            // Final word on the mutes (a volume write unmutes a channel on the device).
            audio.applyMic()
            deck.panelOn = true
            redraw()
        }
    }

    /// Turns the panel off when NexusDeck quits, as the reference app does.
    func shutdown() {
        controller?.sendAndWait(AXProtocol.panelOff())
    }

    private func detach() {
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

    func redraw() {
        guard let c = controller else { return }
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
        if let jpeg = PanelRenderer.jpeg(deck: deck, store: store, images: engine.widgetImages, touched: touchedKey, quality: turning ? 0.45 : 0.8) {
            // An unchanged frame is not sent again: every frame keeps the mixer busy (and slows its knobs).
            guard jpeg != lastFrame else { return }
            lastFrame = jpeg
            lastPush = Date()
            c.push(jpeg: jpeg)
        }
    }

    // MARK: Events

    private func handle(_ e: AXProtocol.Event) {
        switch e {
        case .touch(let x, let y):
            if !deck.panelOn { engine.setPanel(on: true); return }
            if touchStart == nil {
                touchStart = (x, y)
                let cx = min(4, x * 5 / AXProtocol.panelWidth), cy = min(3, y * 4 / AXProtocol.panelHeight)
                touchedKey = deck.key(at: cx, cy)?.id
                if let k = deck.key(at: cx, cy) {
                    if k.actionID.hasPrefix("pkg:") { SDKHost.shared.keyDown(k) }
                    else if ActionCatalog.holdActions.contains(k.actionID) { engine.hold(k, down: true) }
                }
                redraw()
            }
        case .touchUp:
            defer { touchStart = nil; touchedKey = nil; redraw() }
            guard let id = touchedKey, let key = deck.keys(onPage: deck.currentPage).first(where: { $0.id == id }) else { return }
            if key.actionID == ActionID.mixerDashboard { audio.switchActiveMix(); engine.syncStates(); deck.needsRedraw.send(); return }
            if key.actionID.hasPrefix("pkg:") { SDKHost.shared.keyUp(key); return }
            if ActionCatalog.holdActions.contains(key.actionID) { engine.hold(key, down: false); return }
            engine.press(key)
        case .gesture(let g):
            touchedKey = nil
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
