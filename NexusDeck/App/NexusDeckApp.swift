import SwiftUI
import Combine

@main
struct NexusDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("NexusDeck", id: "main") {
            ShellView()
                .withAppEnvironment(app)
                .frame(minWidth: 1320, minHeight: 820)
                .task { app.start(); delegate.app = app }
        }
        .defaultSize(width: 1440, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("NexusDeck", systemImage: "square.grid.3x3.square") {
            MenuBarContent().withAppEnvironment(app)
        }
    }
}

extension View {
    func withAppEnvironment(_ app: AppState) -> some View {
        self.environmentObject(app)
            .environmentObject(app.ui)
            .environmentObject(app.deviceManager)
            .environmentObject(app.store)
            .environmentObject(app.deck)
            .environmentObject(app.editor)
            .environmentObject(app.audio)
            .environmentObject(app.engine)
            .environmentObject(app.engine.obs)
            .environmentObject(app.engine.twitch)
            .environmentObject(app.engine.youtube)
            .environmentObject(app.engine.spotify)
            .environmentObject(app.engine.streamlabs)
            .environmentObject(app.engine.discord)
            .environmentObject(app.bridge)
            .environmentObject(app.appRouter)
    }
}

/// Composition root.
@MainActor
final class AppState: ObservableObject {
    let deviceManager = DeviceManager()
    let store = ProfileStore()
    let deck: DeckController
    let editor: DeckEditorModel
    let audio: AudioService
    let engine: ActionEngine
    let bridge = AudioBridge()
    let appRouter: AppAudioRouter
    let ui = UIState()
    private var session: DeviceSession?
    private var sdkSync: AnyCancellable?
    private var softGainSync: AnyCancellable?
    private var mixSync: AnyCancellable?
    private var loadingSync: AnyCancellable?
    private var linkSync: AnyCancellable?
    private var mixerVisibility: AnyCancellable?
    private var retryObserver: Any?
    private var notFoundWork: DispatchWorkItem?

    /// After 5 s without a ready mixer the overlay turns into the "not found" message.
    private func scheduleNotFound() {
        notFoundWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.deck.deviceReady, !self.ui.closing else { return }
            if !self.deviceManager.state.isConnected && !self.ui.dismissedNotFound {
                self.ui.link = .notFound
                self.ui.loading = true
            } else if self.deviceManager.state.isConnected {
                // Connected but still starting: wait a bit longer.
                self.scheduleNotFound()
            }
        }
        notFoundWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: w)
    }
    private var started = false

    init() {
        deck = DeckController(store: store)
        editor = DeckEditorModel(store: store, deck: deck)
        audio = AudioService(store: store)
        appRouter = AppAudioRouter(store: store)
        engine = ActionEngine(store: store, deck: deck, audio: audio, obs: OBSClient())
    }

    func shutdown() {
        SDKHost.shared.shutdown()
        // Stopping the USB audio makes the mixer reset its LEDs: do it first, then turn them off.
        bridge.stop()
        Thread.sleep(forTimeInterval: 0.8)
        session?.shutdown()
        appRouter.hideAllDevices()
    }

    func start() {
        guard !started else { return }
        started = true
        session = DeviceSession(devices: deviceManager, store: store, deck: deck, audio: audio, engine: engine)
        deviceManager.start()
        bridge.setSingleMix(!store.mixer.dualMix && !store.mixer.obsTracks)
        bridge.start(sampleRate: Double(store.library.device.sampleRate))
        appRouter.start()
        // Mixer link overlay: blurred window while connecting / reconnecting, error after 5 s without a mixer.
        loadingSync = deck.$deviceReady.removeDuplicates().sink { [self] ready in
            if ready { ui.loading = false; ui.dismissedNotFound = false }
        }
        linkSync = deviceManager.$state.map(\.isConnected).removeDuplicates().dropFirst().sink { [self] connected in
            guard !ui.closing else { return }
            if connected {
                ui.link = .connecting
                ui.loading = true
            } else {
                deck.deviceReady = false
                ui.link = .reconnecting
                ui.loading = true
                ui.dismissedNotFound = false
                scheduleNotFound()
            }
        }
        scheduleNotFound()
        retryObserver = NotificationCenter.default.addObserver(forName: .nexusRetryMixer, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleNotFound() }
        }
        // Windows restored from the previous layout can be smaller than the new minimum size.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for w in NSApp.windows where w.styleMask.contains(.titled) && w.frame.width < 1320 {
                var f = w.frame
                f.size = NSSize(width: max(f.width, 1440), height: max(f.height, 880))
                w.setFrame(f, display: true)
                w.center()
            }
        }
        #if DEBUG
        DebugSnapshot.install(ui: ui, editor: editor, deck: deck)
        #endif
        Updater.shared.startAutomaticChecks()
        appRouter.setVisibility(dualMix: store.mixer.dualMix, obsTracks: store.mixer.obsTracks)
        appRouter.setNames(store.mixer)
        // NexusDeck devices only with the mixer connected (they are hidden at start until it is there).
        mixerVisibility = deviceManager.$state.map(\.isConnected).removeDuplicates().sink { [appRouter] c in appRouter.mixerConnected = c }
        mixSync = store.objectWillChange.debounce(for: .milliseconds(200), scheduler: RunLoop.main).sink { [self] _ in
            bridge.setSingleMix(!store.mixer.dualMix && !store.mixer.obsTracks)
            appRouter.setVisibility(dualMix: store.mixer.dualMix, obsTracks: store.mixer.obsTracks)
            appRouter.setNames(store.mixer)
        }
        softGainSync = store.objectWillChange.merge(with: audio.$duckAmount.map { _ in }.eraseToAnyPublisher())
            .debounce(for: .milliseconds(10), scheduler: RunLoop.main).prepend(()).sink { [self] _ in
            let m = store.mixer
            let mix = m.mixes[m.dualMix ? m.activeMix : .creator] ?? MixState()
            func gain(_ ch: MixerChannel) -> Float {
                let c = mix.channels[ch] ?? ChannelState()
                if c.muted || mix.muted { return 0 }
                let v = Float(c.level) / 100 * Float(mix.level) / 100
                return v * v
            }
            bridge.setSoftGains(lineIn: gain(.lineIn), console: gain(.console))
            bridge.setVoice(store.dsp.appVoiceActive ? store.dsp.appVoice : 0, returnGain: audio.voiceReturnGain)
            bridge.setGain(.capSystem, audio.captureGain(.system))
            bridge.setGain(.capGame, audio.captureGain(.game))
            bridge.setGain(.capChat, audio.captureGain(.chat))
            bridge.setGain(.capLineIn, audio.captureGain(.lineIn))
            bridge.setGain(.capConsole, audio.captureGain(.console))
            // The Audience mix applies the Line In at step 20: only the knob's share is added here.
            bridge.setGain(.capLineInHW, m.obsTracks ? audio.captureGain(.lineIn) * 32768 / Float(AudioService.meterGain[20]) : 0)
        }
        engine.startIntegrations()
        SDKHost.shared.start(store: store, deck: deck)
        sdkSync = deck.needsRedraw.debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { SDKHost.shared.syncInstances() }
        runDebugArguments()
        engine.syncStates()
    }

    /// Developer switches: -importLegacy <folder>, -installPackage <url|path>.
    private func runDebugArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-activateProfile"), i + 1 < args.count,
           let p = store.library.hotkeyProfiles.last(where: { $0.title == args[i + 1] }) {
            editor.activate(p.id)
        }
        if let i = args.firstIndex(of: "-pressAll") , i >= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [self] in
                for k in store.hotkey.keys where k.actionID.hasPrefix("pkg:") { SDKHost.shared.press(k) }
            }
        }
        if let i = args.firstIndex(of: "-installPackage"), i + 1 < args.count {
            let s = args[i + 1]
            let url = s.hasPrefix("http") ? URL(string: s)! : URL(fileURLWithPath: s)
            Task { await PackageManager.shared.install(from: url); SDKHost.shared.debugLog("installed: \(PackageManager.shared.packages.map(\.uuid)) error=\(PackageManager.shared.lastError ?? "-")") }
        }
    }
}

/// Quit: the window blurs with "Scollegamento dal mixer…" while the panel plays its closing animation,
/// the LEDs and the panel turn off and the audio devices are hidden; then the app quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppState?
    private var quitting = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let app, !quitting else { return .terminateNow }
        quitting = true
        app.ui.closing = true
        app.ui.loading = true
        // Let the blurred window appear, then do the (blocking) shutdown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            app.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        // Safety net.
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { exit(0) }
        return .terminateLater
    }

    /// "Chiudi applicazione" in the settings: the red button quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: "closeMinimizes") && UserDefaults.standard.object(forKey: "closeMinimizes") != nil
    }
}
