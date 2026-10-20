import Foundation

enum ActionID {
    // Device / mixer
    static let monitor = "mixer.monitor"
    static let micMute = "mixer.micMute"
    static let cough = "mixer.cough"
    static let bleep = "mixer.bleep"
    static let fxPreset = "mixer.fxPreset"
    static let appVoice = "mixer.appVoice"
    static let mixSwitch = "mixer.mixSwitch"
    static let muteChannel = "mixer.mute"
    static let soundboardPlay = "mixer.soundboard.play"
    static let soundboardStop = "mixer.soundboard.stop"
    static let switchHotkeyProfile = "profile.hotkey"
    static let switchKnobProfile = "profile.knob"
    static let switchMixerProfile = "profile.mixer"
    static let switchDSPProfile = "profile.dsp"
    static let pageSwitch = "nav.page"
    static let volume = "mixer.volume"
    static let micEffect = "mixer.micEffect"
    static let multiAction = "system.multiaction"
    static let delay = "system.delay"
    static let panelOff = "system.panelOff"
    static let pageIndicator = "nav.pageIndicator"
    static let group = "nav.group"
    static let groupBack = "nav.groupBack"
    static let mixerDashboard = "widget.mixerDashboard"
    static let webView = "widget.webview"
    // System
    static let openURL = "system.openURL"
    static let openApp = "system.openApp"
    static let hotkey = "system.hotkey"
    static let multimedia = "system.multimedia"
    static let text = "system.text"
    static let window = "system.window"
    // Knob actions
    static let knobInputDevice = "knob.inputDevice"
    static let knobOutputDevice = "knob.outputDevice"
    static let knobOBSVolume = "knob.obsVolume"
    static let knobSpotifyVolume = "knob.spotifyVolume"
    // OBS
    static let obsScene = "obs.scene"
    static let obsMute = "obs.mute"
    static let obsRecord = "obs.record"
    static let obsPauseRecord = "obs.pauseRecord"
    static let obsStream = "obs.stream"
    static let obsSource = "obs.source"
    static let obsCPU = "obs.cpu"
    static let obsVolUp = "obs.volumeUp"
    static let obsVolDown = "obs.volumeDown"
    static let obsVolSet = "obs.volumeSet"
    static let obsMonitorSet = "obs.monitorSet"
    static let obsFilter = "obs.filter"
    static let obsProfile = "obs.profile"
    static let obsCollection = "obs.sceneCollection"
    static let obsTransition = "obs.transition"
    static let obsScenePreview = "obs.scenePreview"
    static let obsStudioPreview = "obs.studioPreview"
    static let obsDroppedFrames = "obs.droppedFrames"
    static let obsHotkey = "obs.hotkey"
    static let obsPrevScene = "obs.previousScene"
    static let obsStudioMode = "obs.studioMode"
    static let obsPreviewToProgram = "obs.previewToProgram"
    static let obsVirtualCam = "obs.virtualCamera"
    // Streamlabs
    static let slMute = "slobs.mute"
    static let slRecord = "slobs.record"
    static let slScene = "slobs.scene"
    static let slSource = "slobs.source"
    static let slStream = "slobs.stream"
    // YouTube
    static let ytWatching = "youtube.watching"
    static let ytSubscribers = "youtube.subscribers"
    static let ytChat = "youtube.chat"
    // Twitch
    static let twViewers = "twitch.viewers"
    static let twFollowers = "twitch.followers"
    static let twChat = "twitch.chat"
    static let twMessage = "twitch.message"
    static let twClearChat = "twitch.clearChat"
    static let twEmoteChat = "twitch.emoteChat"
    static let twFollowersChat = "twitch.followersChat"
    static let twSlowChat = "twitch.slowChat"
    static let twSubChat = "twitch.subChat"
    static let twTitle = "twitch.title"
    static let twMarker = "twitch.marker"
    static let twClip = "twitch.clip"
    static let twLastClip = "twitch.lastClip"
    // Spotify
    static let dcMute = "discord.mute"
    static let dcDeafen = "discord.deafen"
    static let dcPushToTalk = "discord.pushToTalk"
    static let dcPushToMute = "discord.pushToMute"
    static let dcVoiceChannel = "discord.voiceChannel"
    static let dcTextChannel = "discord.textChannel"


    static let spPlayURL = "spotify.playURL"
    static let spPlay = "spotify.play"
    static let spPrev = "spotify.previous"
    static let spNext = "spotify.next"
    static let spVolUp = "spotify.volumeUp"
    static let spVolDown = "spotify.volumeDown"
    static let spShuffle = "spotify.shuffle"
    static let spRepeat = "spotify.repeat"
    static let spNowPlaying = "spotify.nowPlaying"
}

enum ActionKind: String, Codable { case key, widget, knob }

struct ActionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    var kind: ActionKind = .key
    var width = 1
    var height = 1
    var multiAction = true
    var onlyMultiAction = false
    /// Default state titles (toggle actions have two or more).
    var stateTitles: [String] = []
    var stateSymbols: [String] = []
    /// Icon image file (package widgets).
    var iconFile: String? = nil
    /// Alternative sizes ("Multi Layout" in the reference app), the first being the default.
    var layouts: [GridSize] = []
}

struct GridSize: Hashable { let w: Int; let h: Int }

struct ActionCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let actions: [ActionDescriptor]
}

enum ActionCatalog {
    static let categories: [ActionCategory] = [
        ActionCategory(id: "device", title: "NexusDeck", symbol: "slider.horizontal.3", actions: [
            .init(id: ActionID.monitor, title: "Monitor", symbol: "headphones", stateTitles: ["Monitor off", "Monitor"], stateSymbols: ["headphones", "headphones.circle.fill"]),
            .init(id: ActionID.micMute, title: "Muto microfono", symbol: "mic.slash.fill", stateTitles: ["Mic", "Mic muto"], stateSymbols: ["mic.fill", "mic.slash.fill"]),
            .init(id: ActionID.cough, title: "Tasto tosse", symbol: "hand.raised.fill"),
            .init(id: ActionID.bleep, title: "Bip censura", symbol: "exclamationmark.bubble.fill"),
            .init(id: ActionID.appVoice, title: "Voice changer", symbol: "theatermasks.fill", stateTitles: ["Voce", "Voce on"]),
            .init(id: ActionID.fxPreset, title: "Preset effetti voce", symbol: "wand.and.stars", stateTitles: ["Effetti off", "Effetti on"]),
            .init(id: ActionID.mixSwitch, title: "Cambia mix", symbol: "arrow.left.arrow.right", stateTitles: ["Mix 1", "Mix 2"]),
            .init(id: ActionID.muteChannel, title: "Muto", symbol: "speaker.slash.fill", stateTitles: ["Muto off", "Muto"], stateSymbols: ["speaker.wave.2.fill", "speaker.slash.fill"]),
            .init(id: ActionID.soundboardPlay, title: "Soundboard", symbol: "play.square.fill"),
            .init(id: ActionID.soundboardStop, title: "Ferma soundboard", symbol: "stop.fill"),
            .init(id: ActionID.switchHotkeyProfile, title: "Profilo tasti", symbol: "square.grid.3x3", multiAction: false),
            .init(id: ActionID.switchKnobProfile, title: "Profilo manopole", symbol: "dial.medium.fill", multiAction: false),
            .init(id: ActionID.switchMixerProfile, title: "Profilo mixer", symbol: "slider.vertical.3"),
            .init(id: ActionID.switchDSPProfile, title: "Profilo voce", symbol: "waveform"),
            .init(id: ActionID.pageSwitch, title: "Pagina", symbol: "rectangle.on.rectangle"),
            .init(id: ActionID.volume, title: "Volume", symbol: "speaker.wave.2.fill"),
            .init(id: ActionID.micEffect, title: "Effetto microfono", symbol: "waveform.badge.mic", stateTitles: ["Effetto off", "Effetto"]),
            .init(id: ActionID.multiAction, title: "Multi-azione", symbol: "square.stack.3d.down.right.fill", multiAction: false),
            .init(id: ActionID.panelOff, title: "Spegni pannello", symbol: "display"),
            .init(id: ActionID.pageIndicator, title: "Indicatore pagina", symbol: "ellipsis", multiAction: false),
            .init(id: ActionID.group, title: "Cartella", symbol: "folder.fill", multiAction: false),
            .init(id: ActionID.groupBack, title: "Indietro", symbol: "chevron.backward", multiAction: false),
            .init(id: ActionID.mixerDashboard, title: "Dashboard mixer", symbol: "slider.vertical.3", kind: .widget, width: 5, height: 3, multiAction: false),
            .init(id: ActionID.webView, title: "Pagina web", symbol: "globe", kind: .widget, width: 4, height: 3, multiAction: false, layouts: [.init(w: 4, h: 3), .init(w: 2, h: 1), .init(w: 2, h: 2), .init(w: 2, h: 4), .init(w: 3, h: 4), .init(w: 5, h: 4)]),
        ]),
        ActionCategory(id: "system", title: "Sistema", symbol: "macwindow", actions: [
            .init(id: ActionID.openURL, title: "Sito web", symbol: "safari"),
            .init(id: ActionID.openApp, title: "App/File", symbol: "app.badge"),
            .init(id: ActionID.hotkey, title: "Scorciatoia", symbol: "command"),
            .init(id: ActionID.multimedia, title: "Multimedia", symbol: "playpause.fill"),
            .init(id: ActionID.text, title: "Testo", symbol: "text.cursor"),
            .init(id: ActionID.window, title: "Controllo finestre", symbol: "macwindow.on.rectangle"),
        ]),
        ActionCategory(id: "multi", title: "Multi-azione", symbol: "square.stack.3d.down.right", actions: [
            .init(id: ActionID.delay, title: "Ritardo", symbol: "timer", onlyMultiAction: true),
        ]),
        ActionCategory(id: "audio", title: "Controllo audio", symbol: "dial.medium", actions: [
            .init(id: ActionID.knobInputDevice, title: "Dispositivo di ingresso", symbol: "mic.circle", kind: .knob, multiAction: false),
            .init(id: ActionID.knobOutputDevice, title: "Dispositivo di uscita", symbol: "speaker.circle", kind: .knob, multiAction: false),
            .init(id: ActionID.knobOBSVolume, title: "Volume sorgente OBS", symbol: "dial.low", kind: .knob, multiAction: false),
            .init(id: ActionID.knobSpotifyVolume, title: "Volume Spotify", symbol: "dial.high", kind: .knob, multiAction: false),
        ]),
        ActionCategory(id: "obs", title: "OBS Studio", symbol: "record.circle", actions: [
            .init(id: ActionID.obsScene, title: "Scena", symbol: "rectangle.3.group", stateTitles: ["Inattiva", "Scena"]),
            .init(id: ActionID.obsMute, title: "Muto", symbol: "speaker.slash", stateTitles: ["Audio", "Muto"]),
            .init(id: ActionID.obsRecord, title: "Registra", symbol: "record.circle", stateTitles: ["Registra", "Stop"]),
            .init(id: ActionID.obsPauseRecord, title: "Pausa registrazione", symbol: "pause.circle", stateTitles: ["Pausa", "Riprendi"]),
            .init(id: ActionID.obsStream, title: "Diretta", symbol: "dot.radiowaves.left.and.right", stateTitles: ["Avvia diretta", "Ferma diretta"]),
            .init(id: ActionID.obsSource, title: "Sorgente", symbol: "eye", stateTitles: ["Nascosta", "Visibile"]),
            .init(id: ActionID.obsCPU, title: "Uso CPU", symbol: "cpu", kind: .widget, multiAction: false),
            .init(id: ActionID.obsVolUp, title: "Volume sorgente +", symbol: "speaker.plus"),
            .init(id: ActionID.obsVolDown, title: "Volume sorgente −", symbol: "speaker.minus"),
            .init(id: ActionID.obsVolSet, title: "Imposta volume sorgente", symbol: "speaker.wave.3"),
            .init(id: ActionID.obsMonitorSet, title: "Monitor sorgente", symbol: "headphones"),
            .init(id: ActionID.obsFilter, title: "Attiva/disattiva filtro", symbol: "camera.filters", stateTitles: ["Filtro off", "Filtro on"]),
            .init(id: ActionID.obsProfile, title: "Imposta profilo", symbol: "person.crop.square"),
            .init(id: ActionID.obsCollection, title: "Collezione scene", symbol: "square.stack"),
            .init(id: ActionID.obsTransition, title: "Transizione", symbol: "arrow.triangle.swap"),
            .init(id: ActionID.obsScenePreview, title: "Anteprima scena", symbol: "photo.tv", kind: .widget, width: 1, height: 1, multiAction: false, layouts: [.init(w: 1, h: 1), .init(w: 2, h: 2)]),
            .init(id: ActionID.obsStudioPreview, title: "Anteprima Studio Mode", symbol: "rectangle.split.2x1", kind: .widget, width: 1, height: 1, multiAction: false, layouts: [.init(w: 1, h: 1), .init(w: 2, h: 2)]),
            .init(id: ActionID.obsDroppedFrames, title: "Allarme frame persi", symbol: "exclamationmark.triangle", kind: .widget, multiAction: false),
            .init(id: ActionID.obsHotkey, title: "Hotkey OBS", symbol: "keyboard"),
            .init(id: ActionID.obsPrevScene, title: "Scena precedente", symbol: "backward.end"),
            .init(id: ActionID.obsStudioMode, title: "Studio Mode", symbol: "rectangle.split.2x1.fill", stateTitles: ["Studio off", "Studio on"]),
            .init(id: ActionID.obsPreviewToProgram, title: "Anteprima → Programma", symbol: "arrow.right.square"),
            .init(id: ActionID.obsVirtualCam, title: "Camera virtuale", symbol: "web.camera", stateTitles: ["Camera off", "Camera on"]),
        ]),
        ActionCategory(id: "slobs", title: "Streamlabs Desktop", symbol: "s.circle", actions: [
            .init(id: ActionID.slMute, title: "Muto", symbol: "speaker.slash", stateTitles: ["Audio", "Muto"]),
            .init(id: ActionID.slRecord, title: "Registra", symbol: "record.circle", stateTitles: ["Registra", "Stop"]),
            .init(id: ActionID.slScene, title: "Scena", symbol: "rectangle.3.group", stateTitles: ["Inattiva", "Scena"]),
            .init(id: ActionID.slSource, title: "Sorgente", symbol: "eye", stateTitles: ["Nascosta", "Visibile"]),
            .init(id: ActionID.slStream, title: "Diretta", symbol: "dot.radiowaves.left.and.right", stateTitles: ["Avvia diretta", "Ferma diretta"]),
        ]),
        ActionCategory(id: "youtube", title: "YouTube", symbol: "play.rectangle", actions: [
            .init(id: ActionID.ytWatching, title: "Spettatori ora", symbol: "eye", kind: .widget, width: 2, height: 2, multiAction: false, layouts: [.init(w: 2, h: 2), .init(w: 2, h: 1)]),
            .init(id: ActionID.ytSubscribers, title: "Iscritti", symbol: "person.2", kind: .widget, width: 2, height: 2, multiAction: false, layouts: [.init(w: 2, h: 2), .init(w: 2, h: 1)]),
            .init(id: ActionID.ytChat, title: "Chat", symbol: "bubble.left.and.text.bubble.right", kind: .widget, width: 2, height: 4, multiAction: false, layouts: [.init(w: 2, h: 4), .init(w: 2, h: 2), .init(w: 3, h: 4), .init(w: 4, h: 3)]),
        ]),
        ActionCategory(id: "twitch", title: "Twitch", symbol: "tv", actions: [
            .init(id: ActionID.twViewers, title: "Spettatori", symbol: "eye", kind: .widget, width: 2, height: 2, multiAction: false, layouts: [.init(w: 2, h: 2), .init(w: 2, h: 1)]),
            .init(id: ActionID.twFollowers, title: "Follower", symbol: "heart", kind: .widget, width: 2, height: 2, multiAction: false, layouts: [.init(w: 2, h: 2), .init(w: 2, h: 1)]),
            .init(id: ActionID.twChat, title: "Chat", symbol: "bubble.left.and.text.bubble.right", kind: .widget, width: 2, height: 4, multiAction: false, layouts: [.init(w: 2, h: 4), .init(w: 2, h: 2), .init(w: 3, h: 4), .init(w: 4, h: 3)]),
            .init(id: ActionID.twMessage, title: "Messaggio in chat", symbol: "text.bubble"),
            .init(id: ActionID.twClearChat, title: "Pulisci chat", symbol: "trash"),
            .init(id: ActionID.twEmoteChat, title: "Chat solo emote", symbol: "face.smiling", stateTitles: ["Emote off", "Emote on"]),
            .init(id: ActionID.twFollowersChat, title: "Chat solo follower", symbol: "heart.text.square", stateTitles: ["Follower off", "Follower on"]),
            .init(id: ActionID.twSlowChat, title: "Chat lenta", symbol: "tortoise", stateTitles: ["Lenta off", "Lenta on"]),
            .init(id: ActionID.twSubChat, title: "Chat solo abbonati", symbol: "star", stateTitles: ["Abbonati off", "Abbonati on"]),
            .init(id: ActionID.twTitle, title: "Titolo/gioco", symbol: "character.cursor.ibeam"),
            .init(id: ActionID.twMarker, title: "Marcatore", symbol: "bookmark"),
            .init(id: ActionID.twClip, title: "Crea clip", symbol: "scissors"),
            .init(id: ActionID.twLastClip, title: "Apri ultima clip", symbol: "film"),
        ]),
        ActionCategory(id: "discord", title: "Discord", symbol: "bubble.left.and.bubble.right.fill", actions: [
            .init(id: ActionID.dcMute, title: "Muto microfono", symbol: "mic.fill", stateTitles: ["Microfono", "Muto"], stateSymbols: ["mic.fill", "mic.slash.fill"]),
            .init(id: ActionID.dcDeafen, title: "Silenzia audio", symbol: "headphones", stateTitles: ["Audio", "Silenziato"], stateSymbols: ["headphones", "speaker.slash.fill"]),
            .init(id: ActionID.dcPushToTalk, title: "Premi per parlare", symbol: "mic.badge.plus"),
            .init(id: ActionID.dcPushToMute, title: "Premi per silenziare", symbol: "mic.slash"),
            .init(id: ActionID.dcVoiceChannel, title: "Canale vocale", symbol: "speaker.wave.2.bubble.left.fill", stateTitles: ["Entra", "Connesso"], stateSymbols: ["speaker.wave.2.bubble.left", "speaker.wave.2.bubble.left.fill"]),
            .init(id: ActionID.dcTextChannel, title: "Canale testuale", symbol: "number"),
        ]),
        ActionCategory(id: "spotify", title: "Spotify", symbol: "music.note", actions: [
            .init(id: ActionID.spPlay, title: "Play/Pausa", symbol: "playpause.fill", stateTitles: ["Pausa", "Play"]),
            .init(id: ActionID.spPlayURL, title: "Riproduci URL", symbol: "link"),
            .init(id: ActionID.spPrev, title: "Brano precedente", symbol: "backward.fill"),
            .init(id: ActionID.spNext, title: "Brano successivo", symbol: "forward.fill"),
            .init(id: ActionID.spVolUp, title: "Volume +", symbol: "speaker.plus.fill"),
            .init(id: ActionID.spVolDown, title: "Volume −", symbol: "speaker.minus.fill"),
            .init(id: ActionID.spShuffle, title: "Casuale", symbol: "shuffle", stateTitles: ["Casuale off", "Casuale"]),
            .init(id: ActionID.spRepeat, title: "Ripeti", symbol: "repeat", stateTitles: ["Ripeti off", "Ripeti brano", "Ripeti"]),
            .init(id: ActionID.spNowPlaying, title: "In riproduzione", symbol: "music.note.list", kind: .widget, width: 3, height: 2, multiAction: false, layouts: [.init(w: 3, h: 2), .init(w: 2, h: 2), .init(w: 3, h: 1)]),
        ]),
    ]

    static let all: [String: ActionDescriptor] = Dictionary(uniqueKeysWithValues: categories.flatMap(\.actions).map { ($0.id, $0) })

    /// Built-in categories followed by installed SDK packages.
    @MainActor static var allCategories: [ActionCategory] {
        categories.filter { BuiltInIntegration(rawValue: $0.id)?.isEnabled ?? true } + PackageManager.shared.categories
    }

    /// Actions that react to press and release separately (hold to use).
    static let holdActions: Set<String> = [ActionID.dcPushToTalk, ActionID.dcPushToMute, ActionID.cough, ActionID.bleep]

    @MainActor static func descriptor(_ id: String) -> ActionDescriptor {
        if let d = all[id] { return d }
        if id.hasPrefix("pkg:"), let d = PackageManager.shared.categories.flatMap(\.actions).first(where: { $0.id == id }) { return d }
        return ActionDescriptor(id: id, title: id, symbol: "questionmark.square.dashed")
    }

    /// Initial states for a freshly dropped action.
    @MainActor static func defaultStates(for d: ActionDescriptor) -> [KeyState] {
        if let (p, w) = PackageManager.shared.widget(d.id) {
            return w.states.map { KeyState(title: $0.title, image: $0.image.isEmpty ? "" : "file:" + p.file($0.image).path, background: "#000000") }
        }
        let base = Theme.tileHex(for: d.id)
        if d.stateTitles.isEmpty { return [KeyState(title: d.tileLabel, image: "sf:" + d.symbol, background: base)] }
        return d.stateTitles.enumerated().map { i, t in
            let sym = i < d.stateSymbols.count ? d.stateSymbols[i] : d.symbol
            // Same color as the action list; the "on" states are a lighter shade of it.
            return KeyState(title: t, image: "sf:" + sym, background: i == 0 ? base : Theme.lighten(base, 0.28))
        }
    }
}

/// Integrations built into NexusDeck that the user can switch on or off (no download).
/// Integrations built into NexusDeck (always on).
enum BuiltInIntegration: String, CaseIterable, Identifiable {
    case discord
    var id: String { rawValue }
    var defaultsKey: String { "integration.\(rawValue).enabled" }
    var isEnabled: Bool { true }
    var title: String { "Discord" }
    var symbol: String { "bubble.left.and.bubble.right.fill" }
    var summary: String { "Muto, audio, premi per parlare e canali vocali e testuali di Discord." }
    var color: String { "#5865F2" }
}
