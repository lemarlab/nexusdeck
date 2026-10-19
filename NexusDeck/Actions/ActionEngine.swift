import Foundation
import AppKit
import AVFoundation
import Combine

/// Executes key/knob actions and keeps multi-state keys and live widgets in sync with integrations.
@MainActor
final class ActionEngine: ObservableObject {
    let store: ProfileStore
    let deck: DeckController
    let audio: AudioService
    let obs: OBSClient
    let streamlabs = StreamlabsClient()
    let twitch = TwitchClient()
    let youtube = YouTubeClient()
    let spotify = SpotifyClient()
    let discord = DiscordClient()
    let voicemod = VoicemodClient()

    /// Images for widgets that show pictures (OBS previews, Spotify artwork).
    @Published var widgetImages: [UUID: NSImage] = [:]

    private var players: [UUID: AVAudioPlayer] = [:]
    let web = WebSnapshotter()
    private var autoHideTasks: [UUID: Task<Void, Never>] = [:]
    private var previewTimer: Timer?

    init(store: ProfileStore, deck: DeckController, audio: AudioService, obs: OBSClient) {
        self.store = store
        self.deck = deck
        self.audio = audio
        self.obs = obs
        let refresh: () -> Void = { [weak self] in self?.syncStates() }
        obs.onChange = { refresh(); self.obs.noteSceneChange() }
        streamlabs.onChange = refresh
        twitch.onChange = refresh
        youtube.onChange = refresh
        spotify.onChange = refresh
        discord.onChange = refresh
        voicemod.onChange = refresh
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refreshPreviews() } }
        web.onImage = { [weak self] id, img in self?.widgetImages[id] = img; self?.deck.needsRedraw.send() }
        audio.functionKeyColors = { [weak self] in
            guard let self else { return [nil, nil, nil, nil] }
            return (0..<4).map { i in
                self.deck.key(at: i % 2, i / 2, page: self.deck.currentPage, slot: .functionKey).map { k in
                    // Pure black would switch the LED off: use the action's tile color instead.
                    let bg = self.deck.state(for: k).background.uppercased()
                    return bg == "#000000" || bg.isEmpty ? Theme.tileHex(for: k.actionID) : bg
                }
            }
        }
    }

    private var lastLEDState: (Bool, Bool)?

    /// The ambient strip follows the live / recording state (stream first).
    private func updateStatusLEDs() {
        let live = obs.streaming || streamlabs.streaming
        let rec = obs.recording || streamlabs.recording
        guard lastLEDState.map({ $0 != (live, rec) }) ?? true else { return }
        lastLEDState = (live, rec)
        let d = store.library.device
        if !d.interactiveLighting { audio.auraOverride = nil }
        else if live && rec { audio.auraOverride = d.streamFirst ? d.ledStream : d.ledRecord }
        else { audio.auraOverride = live ? d.ledStream : (rec ? d.ledRecord : nil) }
        audio.sendAura(audio.auraOverride ?? d.ledAura)
    }

    func startIntegrations() {
        let s = store.library.integrations
        obs.configure(host: s.obsHost, port: s.obsPort, password: Keychain.get("obs") ?? "")
        if s.obsEnabled { obs.connect() }
        if s.streamlabsEnabled, let token = Keychain.get("streamlabs") { streamlabs.connect(port: s.streamlabsPort, token: token) }
        twitch.clientID = s.twitchClientID
        youtube.clientID = s.youtubeClientID
        youtube.clientSecret = s.youtubeClientSecret
        spotify.clientID = s.spotifyClientID
        Task { await twitch.start() }
        Task { await youtube.start() }
        spotify.start()
        applyBuiltInIntegrations()
    }

    /// Starts or stops Discord / Voicemod according to the switches in the store.
    func applyBuiltInIntegrations() {
        if BuiltInIntegration.discord.isEnabled { discord.start() } else { discord.stop() }
        if BuiltInIntegration.voicemod.isEnabled { voicemod.start() } else { voicemod.stop() }
        objectWillChange.send()
        syncStates()
    }

    /// Press / release for hold-to-use actions (push-to-talk, sounds, bleep).
    func hold(_ key: KeyAssignment, down: Bool) {
        let s = key.settings
        switch key.actionID {
        case ActionID.dcPushToTalk: discord.setMuted(!down)
        case ActionID.dcPushToMute: discord.setMuted(down)
        case ActionID.vmPlaySound: voicemod.playSound(s.string("sound"), down: down)
        case ActionID.vmBleep: voicemod.bleep(down)
        case ActionID.cough:
            audio.setCough(down ? MicMuteMode(rawValue: s.int("mode")) ?? .all : nil)
            syncStates()
        case ActionID.bleep:
            audio.setCough(down ? .all : nil)
            if down { BleepPlayer.shared.start(file: s.string("file"), output: s.string("output", "NexusDeck.System"), volume: Float(s.double("volume", 0.6))) }
            else { BleepPlayer.shared.stop() }
        default: if down { press(key) }
        }
    }

    // MARK: Press

    func press(_ key: KeyAssignment) {
        Task { await run(key) }
    }

    private func nextState(_ key: KeyAssignment) {
        guard key.states.count > 1 else { return }
        deck.setState(key.id, ((deck.stateIndex[key.id] ?? 0) + 1) % key.states.count)
    }

    func run(_ key: KeyAssignment) async {
        let s = key.settings
        switch key.actionID {
        // Navigation
        case ActionID.pageSwitch: deck.go(toPage: s.int("page"))
        case ActionID.group: if let p = s["groupPage"]?.int { deck.enterFolder(p) }
        case ActionID.groupBack: deck.leaveFolder()
        case ActionID.panelOff: setPanel(on: false)
        case ActionID.pageIndicator: deck.nextPage()

        // Profiles
        case ActionID.switchHotkeyProfile:
            if let id = UUID(uuidString: s.string("profile")), store.library.hotkeyProfiles.contains(where: { $0.id == id }) {
                store.library.activeHotkeyProfile = id; deck.profileChanged()
            }
        case ActionID.switchKnobProfile:
            if let id = UUID(uuidString: s.string("profile")) { store.library.activeKnobProfile = id }
        case ActionID.switchMixerProfile:
            if let id = UUID(uuidString: s.string("profile")) { store.library.activeMixerProfile = id; audio.applyMixer(); audio.applyMic() }
        case ActionID.switchDSPProfile:
            if let id = UUID(uuidString: s.string("profile")) { store.library.activeDSPProfile = id }
            else {
                let list = store.library.dspProfiles
                let i = list.firstIndex { $0.id == store.dsp.id } ?? 0
                store.library.activeDSPProfile = list[(i + 1) % list.count].id
            }
            audio.applyDSP()
            deck.setLiveText(key.id, nil)

        // Mixer
        case ActionID.mixerDashboard:
            audio.switchActiveMix()
            deck.needsRedraw.send()
        case ActionID.monitor:
            audio.setMonitor(.mic, bus: .creator, !store.mixer.micMonitor)
        case ActionID.mixSwitch: audio.switchActiveMix()
        case ActionID.muteChannel:
            var targets: [(MixBus, MixerChannel)] = []
            for b in MixBus.allCases { for ch in MixerChannel.allCases where s.bool("\(b.rawValue).\(ch.rawValue)", ch == .mic) { targets.append((b, ch)) } }
            let anyUnmuted = targets.contains { !(store.mixer.mixes[$0.0]?.channels[$0.1]?.muted ?? false) }
            for (b, ch) in targets { audio.setMute(ch, buses: [b], anyUnmuted) }
        case ActionID.volume:
            // "set" is the reference behavior; "up"/"down" are kept for keys made by older NexusDeck versions.
            let ch = s.string("channel", "mic"), mode = s.string("mode", "set"), v = s.int("value", 50)
            func apply(_ cur: Int) -> Int { mode == "set" ? v : (mode == "up" ? cur + v : cur - v) }
            switch ch {
            case "headphones":
                store.library.device.headphonesVolume = max(0, min(100, apply(store.library.device.headphonesVolume))); audio.applyDevice()
            case "lineout":
                store.library.device.lineOutVolume = max(0, min(100, apply(store.library.device.lineOutVolume))); audio.applyDevice()
            default:
                let c = MixerChannel(rawValue: ch) ?? .mic
                let bus = MixBus(rawValue: s.int("mix")) ?? .creator
                audio.setLevel(c, bus: bus, apply(store.mixer.mixes[bus]?.channels[c]?.level ?? 50))
            }
        case ActionID.micEffect:
            switch s.string("effect", "reverb") {
            case "echo": store.dsp.echoEnabled.toggle()
            case "eq": store.dsp.eqEnabled.toggle()
            case "compressor": store.dsp.compressorEnabled.toggle()
            case "gate": store.dsp.noiseGateEnabled.toggle()
            default: store.dsp.reverbEnabled.toggle()
            }
            audio.applyDSP()
        case ActionID.soundboardPlay: playSound(key)
        case ActionID.soundboardStop: players.values.forEach { $0.stop() }; players.removeAll()

        // Multi action
        case ActionID.multiAction:
            for child in key.children {
                if child.actionID == ActionID.delay { try? await Task.sleep(for: .milliseconds(child.settings.int("ms", 500))) }
                else { await run(child) }
            }
        case ActionID.delay: try? await Task.sleep(for: .milliseconds(s.int("ms", 500)))

        // System
        case ActionID.openURL, ActionID.webView:
            var link = s.string("url").trimmingCharacters(in: .whitespaces)
            if !link.isEmpty, !link.contains("://") { link = "https://" + link }
            if let u = URL(string: link), u.scheme != nil { NSWorkspace.shared.open(u) }
        case ActionID.openApp:
            let p = s.string("path")
            if !p.isEmpty { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
        case ActionID.hotkey:
            guard ensureAccessibility() else { return }
            let code = s.int("keyCode", -1)
            if code >= 0 { KeySynth.press(keyCode: UInt16(code), flags: NSEvent.ModifierFlags(rawValue: UInt(s.int("modifiers")))) }
        case ActionID.multimedia: KeySynth.media(MultimediaKey(rawValue: s.string("key", "playPause")) ?? .playPause)
        case ActionID.text:
            guard ensureAccessibility() else { return }
            KeySynth.type(s.string("text"), pressEnter: s.bool("enter"))
        case ActionID.window:
            guard ensureAccessibility() else { return }
            KeySynth.window(WindowOperation(rawValue: s.string("op", "minimize")) ?? .minimize)

        // Discord
        case ActionID.dcMute: discord.toggleMute()
        case ActionID.dcDeafen: discord.toggleDeafen()
        case ActionID.micMute: audio.toggleMicMute(MicMuteMode(rawValue: s.int("mode")) ?? .all)
        case ActionID.fxPreset:
            if fxPresetActive(s) {
                store.dsp.reverbEnabled = false; store.dsp.echoEnabled = false; store.dsp.voiceChanger = .off
            } else {
                store.dsp.reverbEnabled = s.bool("reverb", true)
                store.dsp.reverbPresetIndex = s.int("reverbPreset", 1)
                store.dsp.echoEnabled = s.bool("echo")
                store.dsp.voiceChanger = VoiceChanger(rawValue: s.int("voice")) ?? .off
            }
            audio.applyDSP()
        case ActionID.dcPushToTalk, ActionID.dcPushToMute, ActionID.vmPlaySound, ActionID.vmBleep, ActionID.cough, ActionID.bleep:
            // From a multi-action or a click in the editor: a short press.
            hold(key, down: true)
            try? await Task.sleep(for: .milliseconds(key.actionID == ActionID.vmPlaySound ? 50 : 300))
            hold(key, down: false)
        case ActionID.dcVoiceChannel: discord.toggleVoice(s.string("channel"))
        case ActionID.dcTextChannel: discord.openText(s.string("channel"))

        // Voicemod
        case ActionID.vmVoice: voicemod.loadVoice(s.string("voice"))
        case ActionID.vmToggleChanger: voicemod.toggleChanger()
        case ActionID.vmActivateChanger: voicemod.activateChanger()
        case ActionID.vmBackground: voicemod.toggleBackground()
        case ActionID.vmHearMyself: voicemod.toggleHearMyself()
        case ActionID.vmMute: voicemod.toggleMute()
        case ActionID.vmMuteForMe: voicemod.toggleMuteForMe()
        case ActionID.vmStopSounds: voicemod.stopAllSounds()

        case ActionID.spPlayURL: await spotify.play(url: s.string("url"))

        // OBS
        case ActionID.obsScene: await obs.setScene(s.string("scene"))
        case ActionID.obsMute: await obs.toggleMute(s.string("input"))
        case ActionID.obsRecord: await obs.toggleRecord()
        case ActionID.obsPauseRecord: await obs.toggleRecordPause()
        case ActionID.obsStream: await obs.toggleStream()
        case ActionID.obsSource:
            if let visible = await obs.toggleSource(scene: s.string("scene"), source: s.string("source")), visible, s.bool("autoHide") {
                autoHideTasks[key.id]?.cancel()
                autoHideTasks[key.id] = Task {
                    try? await Task.sleep(for: .seconds(s.int("autoHideTime", 20)))
                    if !Task.isCancelled { await obs.setSource(scene: s.string("scene"), source: s.string("source"), enabled: false) }
                }
            }
        case ActionID.obsVolUp: await obs.changeVolume(s.string("input"), by: Double(s.int("step", 5)))
        case ActionID.obsVolDown: await obs.changeVolume(s.string("input"), by: -Double(s.int("step", 5)))
        case ActionID.obsVolSet: await obs.setVolumePercent(s.string("input"), s.double("volume", 100))
        case ActionID.obsMonitorSet: await obs.setMonitorType(s.string("input"), s.string("monitor", "OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT"))
        case ActionID.obsFilter:
            if let on = await obs.toggleFilter(source: s.string("source"), filter: s.string("filter")) { deck.setState(key.id, on ? 1 : 0) }
        case ActionID.obsProfile: await obs.setProfile(s.string("profile"))
        case ActionID.obsCollection: await obs.setCollection(s.string("collection"))
        case ActionID.obsTransition: await obs.setTransition(s.string("transition"))
        case ActionID.obsHotkey: await obs.triggerHotkey(s.string("hotkey"))
        case ActionID.obsPrevScene: await obs.previousScene()
        case ActionID.obsStudioMode: await obs.toggleStudioMode()
        case ActionID.obsPreviewToProgram: await obs.previewToProgram()
        case ActionID.obsVirtualCam: await obs.toggleVirtualCam()
        case ActionID.obsScenePreview: await obs.setScene(s.string("scene"))
        case ActionID.obsStudioPreview: await obs.previewToProgram()
        case ActionID.obsDroppedFrames, ActionID.obsCPU: break

        // Streamlabs
        case ActionID.slScene: await streamlabs.setScene(s.string("scene"))
        case ActionID.slMute: await streamlabs.toggleMute(s.string("input"))
        case ActionID.slRecord: await streamlabs.toggleRecord()
        case ActionID.slStream: await streamlabs.toggleStream()
        case ActionID.slSource: await streamlabs.toggleSource(scene: s.string("scene"), source: s.string("source"))

        // Twitch
        case ActionID.twMessage: twitch.sendMessage(s.string("message"))
        case ActionID.twClearChat: await twitch.clearChat()
        case ActionID.twEmoteChat: await twitch.toggleEmoteOnly()
        case ActionID.twFollowersChat: await twitch.toggleFollowersOnly()
        case ActionID.twSlowChat: await twitch.toggleSlow(seconds: s.int("seconds", 30))
        case ActionID.twSubChat: await twitch.toggleSubOnly()
        case ActionID.twTitle: await twitch.setTitle(s.string("title"), game: s.string("game"))
        case ActionID.twMarker: await twitch.createMarker()
        case ActionID.twClip: await twitch.createClip()
        case ActionID.twLastClip: twitch.openLastClip()

        // Spotify
        case ActionID.spPlay: await spotify.playPause()
        case ActionID.spPrev: await spotify.previous()
        case ActionID.spNext: await spotify.next()
        case ActionID.spVolUp: await spotify.changeVolume(s.int("step", 10))
        case ActionID.spVolDown: await spotify.changeVolume(-s.int("step", 10))
        case ActionID.spShuffle: await spotify.toggleShuffle()
        case ActionID.spRepeat: await spotify.cycleRepeat()
        default:
            if key.actionID.hasPrefix("pkg:") { SDKHost.shared.press(key) } else { nextState(key) }
        }
        syncStates()
    }

    private func ensureAccessibility() -> Bool {
        if KeySynth.hasAccessibility { return true }
        KeySynth.requestAccessibility()
        return false
    }

    private func playSound(_ key: KeyAssignment) {
        let s = key.settings
        let mode = s.string("mode", "toggle")
        if let p = players[key.id], p.isPlaying, mode == "toggle" || mode == "loop" { p.stop(); players[key.id] = nil; syncStates(); return }
        guard let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: s.string("file"))) else { return }
        player.volume = Float(s.double("volume", 1))
        // Empty = macOS default output.
        let output = s.string("output")
        if !output.isEmpty { player.currentDevice = output }
        if mode == "loop" { player.numberOfLoops = -1 }
        if mode == "overlap" { players[UUID()] = player } else { players[key.id]?.stop(); players[key.id] = player }
        player.play()
    }

    /// The voice effects of a preset key are currently applied.
    private func fxPresetActive(_ s: Settings) -> Bool {
        let d = store.dsp
        let voice = VoiceChanger(rawValue: s.int("voice")) ?? .off
        let anyOn = d.reverbEnabled || d.echoEnabled || d.voiceChanger != .off
        return anyOn && d.reverbEnabled == s.bool("reverb", true) && d.echoEnabled == s.bool("echo") && d.voiceChanger == voice
            && (!d.reverbEnabled || d.reverbPresetIndex == s.int("reverbPreset", 1))
    }

    func setPanel(on: Bool) {
        deck.panelOn = on
        audio.controller?.send(on ? AXProtocol.panelOn() : AXProtocol.panelOff())
        if on { audio.controller?.send(AXProtocol.backlight(store.library.device.brightness)) }
        deck.needsRedraw.send()
    }

    // MARK: Knobs

    /// Relative knob turn for knobs bound to a custom action.
    func knobTurned(_ index: Int, delta: Int) -> Bool {
        let k = store.knob.knobs[index]
        guard let id = k.actionID else { return false }
        let step = Double(k.settings.int("step", 2) * delta)
        switch id {
        case ActionID.knobInputDevice, ActionID.knobOutputDevice:
            let input = id == ActionID.knobInputDevice
            let dev = SystemAudio.device(uid: k.settings.string("uid"), input: input)
            SystemAudio.setVolume(dev, input: input, SystemAudio.volume(dev, input: input) + Float(step / 100))
        case ActionID.knobOBSVolume: Task { await obs.changeVolume(k.settings.string("input"), by: step) }
        case ActionID.knobSpotifyVolume: Task { await spotify.changeVolume(Int(step)) }
        default: return false
        }
        return true
    }

    func knobPressed(_ index: Int) {
        let k = store.knob.knobs[index]
        guard let id = k.actionID else {
            audio.toggleMute(MixerChannel.allCases[index], bus: store.mixer.activeMix)
            return
        }
        guard k.settings.string("press", "mute") == "mute" else { return }
        switch id {
        case ActionID.knobInputDevice, ActionID.knobOutputDevice:
            let input = id == ActionID.knobInputDevice
            let dev = SystemAudio.device(uid: k.settings.string("uid"), input: input)
            SystemAudio.setMuted(dev, input: input, !SystemAudio.isMuted(dev, input: input))
        case ActionID.knobOBSVolume: Task { await obs.toggleMute(k.settings.string("input")) }
        case ActionID.knobSpotifyVolume: Task { await spotify.playPause() }
        default: break
        }
    }

    // MARK: State sync

    func syncStates() {
        let all = store.hotkey.keys + store.hotkey.keys.flatMap(\.children)
        for k in all {
            let s = k.settings
            var state: Int?
            var text: String?
            switch k.actionID {
            case ActionID.obsScene: state = obs.programScene == s.string("scene") ? 1 : 0
            case ActionID.obsRecord: state = obs.recording ? 1 : 0
            case ActionID.obsPauseRecord: state = obs.recordPaused ? 1 : 0
            case ActionID.obsStream: state = obs.streaming ? 1 : 0
            case ActionID.obsVirtualCam: state = obs.virtualCam ? 1 : 0
            case ActionID.obsStudioMode: state = obs.studioMode ? 1 : 0
            case ActionID.obsMute: state = (obs.inputMuted[s.string("input")] ?? false) ? 1 : 0
            case ActionID.obsSource:
                state = (obs.sceneItemsByScene[s.string("scene")]?.first { $0.name == s.string("source") }?.enabled ?? false) ? 1 : 0
            case ActionID.obsCPU: text = obs.isConnected ? String(format: "%.1f%%", obs.cpuUsage) : "—"
            case ActionID.obsDroppedFrames: text = obs.isConnected ? "\(obs.skippedFrames)" : "—"
            case ActionID.slScene: state = streamlabs.activeScene == s.string("scene") ? 1 : 0
            case ActionID.slRecord: state = streamlabs.recording ? 1 : 0
            case ActionID.slStream: state = streamlabs.streaming ? 1 : 0
            case ActionID.slMute: state = (streamlabs.muted[s.string("input")] ?? false) ? 1 : 0
            case ActionID.twViewers: text = "\(twitch.viewers)"
            case ActionID.twFollowers: text = "\(twitch.followers)"
            case ActionID.twEmoteChat: state = twitch.emoteOnly ? 1 : 0
            case ActionID.twFollowersChat: state = twitch.followersOnly ? 1 : 0
            case ActionID.twSlowChat: state = twitch.slowMode ? 1 : 0
            case ActionID.dcMute: state = discord.muted ? 1 : 0
            case ActionID.dcDeafen: state = discord.deafened ? 1 : 0
            case ActionID.dcVoiceChannel: state = !s.string("channel").isEmpty && discord.voiceChannel == s.string("channel") ? 1 : 0
            case ActionID.vmToggleChanger: state = voicemod.changerOn ? 1 : 0
            case ActionID.vmBackground: state = voicemod.backgroundOn ? 1 : 0
            case ActionID.vmHearMyself: state = voicemod.hearOn ? 1 : 0
            case ActionID.vmMute: state = voicemod.micMuted ? 1 : 0
            case ActionID.vmMuteForMe: state = voicemod.muteForMeOn ? 1 : 0
            case ActionID.vmVoice:
                if let img = voicemod.image(voice: s.string("voice")) { widgetImages[k.id] = img }
            case ActionID.vmPlaySound:
                if let img = voicemod.image(sound: s.string("sound")) { widgetImages[k.id] = img }
            case ActionID.twSubChat: state = twitch.subOnly ? 1 : 0
            case ActionID.twChat: text = twitch.chat.suffix(4).map { "\($0.author): \($0.text)" }.joined(separator: "\n")
            case ActionID.ytWatching: text = "\(youtube.watching)"
            case ActionID.ytSubscribers: text = "\(youtube.subscribers)"
            case ActionID.ytChat: text = youtube.chat.suffix(4).map { "\($0.author): \($0.text)" }.joined(separator: "\n")
            case ActionID.spPlay: state = spotify.isPlaying ? 1 : 0
            case ActionID.spShuffle: state = spotify.shuffle ? 1 : 0
            case ActionID.spRepeat: state = spotify.repeatMode == "off" ? 0 : (spotify.repeatMode == "track" ? 1 : 2)
            case ActionID.spNowPlaying:
                text = spotify.track.isEmpty ? "—" : "\(spotify.track)\n\(spotify.artist)"
                if let a = spotify.artwork { widgetImages[k.id] = a }
            case ActionID.monitor:
                state = store.mixer.micMonitor ? 1 : 0
            case ActionID.micMute:
                switch MicMuteMode(rawValue: s.int("mode")) ?? .all {
                case .all: state = audio.micInStream || !store.mixer.chatMicMuted ? 0 : 1
                case .stream: state = audio.micInStream ? 0 : 1
                case .chat: state = store.mixer.chatMicMuted ? 1 : 0
                }
            case ActionID.fxPreset: state = fxPresetActive(s) ? 1 : 0
            case ActionID.mixSwitch: state = store.mixer.activeMix.rawValue
            case ActionID.muteChannel:
                let anyMuted = MixBus.allCases.contains { b in MixerChannel.allCases.contains { ch in s.bool("\(b.rawValue).\(ch.rawValue)", ch == .mic) && (store.mixer.mixes[b]?.channels[ch]?.muted ?? false) } }
                state = anyMuted ? 1 : 0
            case ActionID.micEffect:
                let on: Bool
                switch s.string("effect", "reverb") {
                case "echo": on = store.dsp.echoEnabled
                case "eq": on = store.dsp.eqEnabled
                case "compressor": on = store.dsp.compressorEnabled
                case "gate": on = store.dsp.noiseGateEnabled
                default: on = store.dsp.reverbEnabled
                }
                state = on ? 1 : 0
            case ActionID.volume:
                let ch = s.string("channel", "mic")
                if let c = MixerChannel(rawValue: ch) { text = "\(store.mixer.mixes[MixBus(rawValue: s.int("mix")) ?? .creator]?.channels[c]?.level ?? 0)" }
                else { text = "\(ch == "headphones" ? store.library.device.headphonesVolume : store.library.device.lineOutVolume)" }
            case ActionID.switchDSPProfile: text = s.string("profile").isEmpty ? store.dsp.title : nil
            default: continue
            }
            if let state, k.states.count > 1 { deck.setState(k.id, min(state, k.states.count - 1)) }
            if let text { deck.setLiveText(k.id, text) }
        }
        updateStatusLEDs()
        deck.needsRedraw.send()
    }

    private func refreshPreviews() async {
        web.update(keys: deck.keys(onPage: deck.currentPage))
        web.snapshotAll()
        guard obs.isConnected else { return }
        for k in deck.keys(onPage: deck.currentPage) {
            switch k.actionID {
            case ActionID.obsScenePreview:
                let scene = k.settings.string("scene").isEmpty ? obs.programScene : k.settings.string("scene")
                if let img = await obs.screenshot(of: scene) { widgetImages[k.id] = img }
            case ActionID.obsStudioPreview:
                if let img = await obs.screenshot(of: obs.studioMode ? obs.previewScene : obs.programScene) { widgetImages[k.id] = img }
            default: continue
            }
        }
        deck.needsRedraw.send()
    }
}
