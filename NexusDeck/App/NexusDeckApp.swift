import SwiftUI
import Combine

@main
struct NexusDeckApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("NexusDeck", id: "main") {
            ShellView()
                .withAppEnvironment(app)
                .frame(minWidth: 1127, minHeight: 917)
                .task { app.start() }
        }
        .defaultSize(width: 1127, height: 917)
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
            .environmentObject(app.engine.voicemod)
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
    private var started = false

    init() {
        deck = DeckController(store: store)
        editor = DeckEditorModel(store: store, deck: deck)
        audio = AudioService(store: store)
        appRouter = AppAudioRouter(store: store)
        engine = ActionEngine(store: store, deck: deck, audio: audio, obs: OBSClient())
    }

    func start() {
        guard !started else { return }
        started = true
        session = DeviceSession(devices: deviceManager, store: store, deck: deck, audio: audio, engine: engine)
        deviceManager.start()
        bridge.setSingleMix(!store.mixer.dualMix)
        bridge.start(sampleRate: Double(store.library.device.sampleRate))
        appRouter.start()
        mixSync = store.objectWillChange.debounce(for: .milliseconds(200), scheduler: RunLoop.main).sink { [self] _ in
            bridge.setSingleMix(!store.mixer.dualMix)
        }
        softGainSync = store.objectWillChange.debounce(for: .milliseconds(30), scheduler: RunLoop.main).prepend(()).sink { [self] _ in
            let m = store.mixer
            let mix = m.mixes[m.dualMix ? m.activeMix : .creator] ?? MixState()
            func gain(_ ch: MixerChannel) -> Float {
                let c = mix.channels[ch] ?? ChannelState()
                if c.muted || mix.muted { return 0 }
                let v = Float(c.level) / 100 * Float(mix.level) / 100
                return v * v
            }
            bridge.setSoftGains(lineIn: gain(.lineIn), console: gain(.console))
        }
        engine.startIntegrations()
        SDKHost.shared.start(store: store, deck: deck)
        sdkSync = deck.needsRedraw.debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { SDKHost.shared.syncInstances() }
        runDebugArguments()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { SDKHost.shared.shutdown(); self?.session?.shutdown() } }
        engine.syncStates()
    }

    /// Developer switches: -importLegacy <folder>, -installPackage <url|path>.
    private func runDebugArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-importLegacy"), i + 1 < args.count {
            let r = LegacyImporter.run(folder: URL(fileURLWithPath: args[i + 1]), into: store)
            deck.profileChanged()
            SDKHost.shared.debugLog("import: \(r.hotkeyProfiles) hotkey, \(r.keys) keys, \(r.mixerProfiles) mixer, \(r.dspProfiles) dsp, missing=\(r.missingPackages.sorted()), unknown=\(r.unknownActions.sorted())")
        }
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
