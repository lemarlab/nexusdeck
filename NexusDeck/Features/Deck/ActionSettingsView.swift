import SwiftUI

extension Binding where Value == Settings {
    func string(_ k: String, _ d: String = "") -> Binding<String> {
        Binding<String>(get: { wrappedValue.string(k, d) }, set: { wrappedValue[k] = .string($0) })
    }
    func int(_ k: String, _ d: Int = 0) -> Binding<Int> {
        Binding<Int>(get: { wrappedValue.int(k, d) }, set: { wrappedValue[k] = .number(Double($0)) })
    }
    func double(_ k: String, _ d: Double = 0) -> Binding<Double> {
        Binding<Double>(get: { wrappedValue.double(k, d) }, set: { wrappedValue[k] = .number($0) })
    }
    func bool(_ k: String, _ d: Bool = false) -> Binding<Bool> {
        Binding<Bool>(get: { wrappedValue.bool(k, d) }, set: { wrappedValue[k] = .bool($0) })
    }
}

/// Text field with an optional list of suggestions coming from a live integration.
struct SuggestField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let options: [String]

    var body: some View {
        HStack {
            TextField(title, text: $text)
            if !options.isEmpty {
                Menu {
                    ForEach(options, id: \.self) { o in Button(o) { text = o } }
                } label: { Image(systemName: "list.bullet") }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
    }
}

enum MultimediaKey: String, CaseIterable, Identifiable {
    case playPause, next, previous, volumeUp, volumeDown, mute
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .playPause: "Play/Pausa"
        case .next: "Successivo"
        case .previous: "Precedente"
        case .volumeUp: "Volume +"
        case .volumeDown: "Volume −"
        case .mute: "Muto"
        }
    }
}

enum WindowOperation: String, CaseIterable, Identifiable {
    case minimize, zoom, close, fullScreen, hideApp, nextWindow, leftHalf, rightHalf, center
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .minimize: "Riduci a icona"
        case .zoom: "Ingrandisci"
        case .close: "Chiudi finestra"
        case .fullScreen: "Schermo intero"
        case .hideApp: "Nascondi app"
        case .nextWindow: "Finestra successiva"
        case .leftHalf: "Metà sinistra"
        case .rightHalf: "Metà destra"
        case .center: "Centra"
        }
    }
}

struct ActionSettingsView: View {
    @Binding var key: KeyAssignment
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var engine: ActionEngine
    @EnvironmentObject var obs: OBSClient
    @EnvironmentObject var discord: DiscordClient
    @EnvironmentObject var voicemod: VoicemodClient
    @EnvironmentObject var editor: DeckEditorModel

    var body: some View {
        Form {
            let layouts = ActionCatalog.descriptor(key.actionID).layouts
            if layouts.count > 1 && key.slot == .touch && key.actionID != ActionID.webView {
                DropdownRowField(title: "Layout", selection: Binding(get: { "\(key.w)x\(key.h)" }, set: { v in
                    let p = v.split(separator: "x").compactMap { Int($0) }
                    if p.count == 2, !editor.resize(key.id, w: p[0], h: p[1]) { editor.message = "Spazio insufficiente per questo layout." }
                }), options: layouts.map { ("\($0.w)x\($0.h)", "\($0.w) × \($0.h)") })
            }
            settings(for: key.actionID, $key.settings)
            if key.actionID == ActionID.multiAction {
                MultiActionEditor(children: $key.children)
            }
        }
        .formStyle(.columns)
        .font(.system(size: 12))
        .foregroundStyle(Theme.textMid)
    }

    @ViewBuilder
    func settings(for id: String, _ s: Binding<Settings>) -> some View {
        switch id {
        case ActionID.openURL:
            TextField("URL", text: s.string("url"))
        case ActionID.micMute, ActionID.cough:
            DropdownRowField(title: "Silenzia", selection: s.int("mode", 0),
                             options: [(0, "Ovunque (cuffie, diretta e chat)"), (1, "Solo diretta"), (2, "Solo chat (Chat Mic)")])
            if id == ActionID.cough { Text("Tieni premuto il tasto per silenziare, rilascialo per riattivare.").foregroundStyle(.secondary) }
        case ActionID.bleep:
            Text("Tieni premuto: il microfono si silenzia e parte il bip finché non rilasci.").foregroundStyle(.secondary)
            HStack {
                TextField("Suono (vuoto = bip 1 kHz)", text: s.string("file"))
                Button("Scegli…") {
                    let p = NSOpenPanel(); p.allowedContentTypes = [.audio]
                    if p.runModal() == .OK, let u = p.url { s.wrappedValue["file"] = .string(u.path) }
                }
            }
            DropdownRowField(title: "Uscita", selection: s.string("output", "NexusDeck.System"),
                             options: SystemAudio.outputDevices().map { ($0.uid, $0.name) })
            Slider(value: s.double("volume", 0.6), in: 0...1) { Text("Volume") }
        case ActionID.fxPreset:
            Toggle("Riverbero", isOn: s.bool("reverb", true))
            if s.wrappedValue.bool("reverb", true) {
                DropdownRowField(title: "Ambiente", selection: s.int("reverbPreset", 1), options: [(0, "Stanza piccola"), (1, "Spazio piccolo"), (2, "Sala"), (3, "Spazio ampio")])
            }
            Toggle("Eco", isOn: s.bool("echo"))
            DropdownRowField(title: "Voice changer", selection: s.int("voice", 0),
                             options: [(0, "Nessuno"), (1, "Robot"), (2, "Mostro"), (3, "Bambino"), (4, "Alieno"), (5, "Radio")])
            Text("Premi per attivare la combinazione, premi di nuovo per spegnere gli effetti.").foregroundStyle(.secondary)
        case ActionID.spPlayURL:
            TextField("URL Spotify", text: s.string("url"), prompt: Text("https://open.spotify.com/…"))
            if !s.wrappedValue.string("url").isEmpty && SpotifyClient.uri(from: s.wrappedValue.string("url")) == nil {
                Text("Incolla il link di un brano, album, playlist o artista di Spotify.").foregroundStyle(.secondary)
            }
        case ActionID.webView:
            TextField("URL", text: s.string("url"))
            DropdownRowField(title: "Dimensione (L × A)", selection: Binding(get: { "\(key.w)x\(key.h)" }, set: { v in
                let p = v.split(separator: "x").compactMap { Int($0) }
                if p.count == 2, !editor.resize(key.id, w: p[0], h: p[1]) { editor.message = "Spazio insufficiente per questa dimensione." }
            }), options: WebSnapshotter.layouts.map { ("\($0.w)x\($0.h)", "\($0.w) × \($0.h)") })
            LabeledContent("CSS personalizzato") {
                TextEditor(text: s.string("customCss", WebSnapshotter.defaultCSS))
                    .font(.system(size: 11, design: .monospaced)).frame(height: 70)
            }
            HStack {
                Button("Interagisci") { engine.web.openInteractive(s.wrappedValue.string("url")) }
                    .help("Apri la finestra del browser")
                Button("Aggiorna la pagina") { engine.web.reload(key.id) }
            }
        case ActionID.openApp:
            HStack {
                TextField("Percorso", text: s.string("path"))
                Button("Scegli…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true
                    if p.runModal() == .OK, let u = p.url { s.wrappedValue["path"] = .string(u.path) }
                }
            }
        case ActionID.hotkey:
            HotkeyRecorder(settings: s)
        case ActionID.multimedia:
            DropdownRowField(title: "Tasto", selection: s.string("key", MultimediaKey.playPause.rawValue), options: MultimediaKey.allCases.map { ($0.rawValue, $0.title) })
        case ActionID.text:
            TextField("Testo da digitare", text: s.string("text"), axis: .vertical).lineLimit(3...6)
            Toggle("Premi Invio alla fine", isOn: s.bool("enter"))
        case ActionID.window:
            DropdownRowField(title: "Operazione", selection: s.string("op", WindowOperation.minimize.rawValue), options: WindowOperation.allCases.map { ($0.rawValue, $0.title) })
        case ActionID.delay:
            Stepper("Ritardo: \(s.wrappedValue.int("ms", 500)) ms", value: s.int("ms", 500), in: 0...60000, step: 100)
        case ActionID.pageSwitch:
            DropdownRowField(title: "Vai alla pagina", selection: s.int("page"), options: (0..<store.hotkey.pageCount).map { ($0, "Pagina \($0 + 1)") })
        case ActionID.switchHotkeyProfile:
            DropdownRowField(title: "Profilo", selection: s.string("profile"), options: store.library.hotkeyProfiles.map { ($0.id.uuidString, $0.title) })
        case ActionID.switchKnobProfile:
            DropdownRowField(title: "Profilo", selection: s.string("profile"), options: store.library.knobProfiles.map { ($0.id.uuidString, $0.title) })
        case ActionID.switchMixerProfile:
            DropdownRowField(title: "Profilo", selection: s.string("profile"), options: store.library.mixerProfiles.map { ($0.id.uuidString, $0.title) })
        case ActionID.switchDSPProfile:
            DropdownRowField(title: "Profilo", selection: s.string("profile"), options: [("", "Successivo (ciclico)")] + store.library.dspProfiles.map { ($0.id.uuidString, $0.title) })
        case ActionID.muteChannel:
            ForEach(MixBus.allCases) { bus in
                Section(bus.title) {
                    ForEach(MixerChannel.allCases) { ch in
                        Toggle(ch.title, isOn: s.bool("\(bus.rawValue).\(ch.rawValue)", ch == .mic))
                    }
                }
            }
        case ActionID.monitor:
            DropdownRowField(title: "Canale", selection: s.string("channel", MixerChannel.mic.rawValue), options: MixerChannel.allCases.map { ($0.rawValue, $0.title) })
        case ActionID.volume:
            // As in the reference app: source, mix ("Mode") and the volume to set.
            DropdownRowField(title: "Seleziona sorgente", selection: s.string("channel", MixerChannel.mic.rawValue),
                             options: MixerChannel.allCases.map { ($0.rawValue, $0.title) })
            DropdownRowField(title: "Modalità", selection: s.int("mix", 0), options: [(0, "Creator / Master Mix"), (1, "Audience Mix")])
            LabeledContent("Volume") {
                HStack(spacing: 6) {
                    TextField("", value: Binding(get: { s.wrappedValue.int("value", 50) },
                                                 set: { s.wrappedValue["value"] = .number(Double(max(0, min(100, $0)))); s.wrappedValue["mode"] = .string("set") }),
                              format: .number).frame(width: 52)
                    Stepper("", value: Binding(get: { s.wrappedValue.int("value", 50) },
                                               set: { s.wrappedValue["value"] = .number(Double($0)); s.wrappedValue["mode"] = .string("set") }), in: 0...100).labelsHidden()
                }
            }
        case ActionID.micEffect:
            DropdownRowField(title: "Effetto", selection: s.string("effect", "reverb"),
                             options: [("reverb", "Riverbero"), ("echo", "Eco"), ("eq", "Equalizzatore"), ("compressor", "Compressore"), ("gate", "Noise gate")])
        case ActionID.soundboardPlay:
            HStack {
                TextField("File audio", text: s.string("file"))
                Button("Scegli…") {
                    let p = NSOpenPanel(); p.allowedContentTypes = [.audio]
                    if p.runModal() == .OK, let u = p.url { s.wrappedValue["file"] = .string(u.path) }
                }
            }
            DropdownRowField(title: "Uscita", selection: s.string("output"), options: [("", "Uscita predefinita di macOS")] + SystemAudio.outputDevices().map { ($0.uid, $0.name) })
            Slider(value: s.double("volume", 1), in: 0...1) { Text("Volume") }
            DropdownRowField(title: "Alla pressione", selection: s.string("mode", "toggle"),
                             options: [("toggle", "Play / Stop"), ("restart", "Play / Riavvia"), ("loop", "Loop / Stop")] + (s.wrappedValue["mode"]?.string == "overlap" ? [("overlap", "Sovrapponi")] : []))
        case ActionID.obsScene, ActionID.slScene:
            SuggestField(title: "Scena", text: s.string("scene"), options: id == ActionID.obsScene ? obs.sceneNames : engine.streamlabs.sceneNames)
        case ActionID.obsScenePreview:
            SuggestField(title: "Scena", text: s.string("scene"), options: obs.sceneNames)
        case ActionID.obsSource, ActionID.slSource:
            SuggestField(title: "Scena", text: s.string("scene"), options: id == ActionID.obsSource ? obs.sceneNames : engine.streamlabs.sceneNames)
            SuggestField(title: "Sorgente", text: s.string("source"), options: id == ActionID.obsSource ? obs.sceneItems(s.wrappedValue.string("scene")) : engine.streamlabs.sourceNames)
            Toggle("Nascondi automaticamente", isOn: s.bool("autoHide"))
            if s.wrappedValue.bool("autoHide") { Stepper("Dopo \(s.wrappedValue.int("autoHideTime", 20)) s", value: s.int("autoHideTime", 20), in: 1...600) }
        case ActionID.obsMute, ActionID.slMute, ActionID.obsVolUp, ActionID.obsVolDown, ActionID.obsVolSet, ActionID.obsMonitorSet:
            SuggestField(title: "Sorgente audio", text: s.string("input"), options: id.hasPrefix("obs") ? obs.inputNames : engine.streamlabs.audioSourceNames)
            if id == ActionID.obsVolUp || id == ActionID.obsVolDown {
                Stepper("Passo: \(s.wrappedValue.int("step", 5)) %", value: s.int("step", 5), in: 1...50)
            }
            if id == ActionID.obsVolSet {
                Slider(value: s.double("volume", 100), in: 0...100) { Text("Volume \(Int(s.wrappedValue.double("volume", 100)))%") }
            }
            if id == ActionID.obsMonitorSet {
                DropdownRowField(title: "Monitor", selection: s.string("monitor", "OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT"),
                                 options: [("OBS_MONITORING_TYPE_NONE", "Disattivato"), ("OBS_MONITORING_TYPE_MONITOR_ONLY", "Solo monitor"), ("OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT", "Monitor e uscita")])
            }
        case ActionID.obsFilter:
            SuggestField(title: "Sorgente", text: s.string("source"), options: obs.sceneNames + obs.inputNames)
            TextField("Filtro", text: s.string("filter"))
        case ActionID.obsProfile:
            SuggestField(title: "Profilo", text: s.string("profile"), options: obs.profiles)
        case ActionID.obsCollection:
            SuggestField(title: "Collezione", text: s.string("collection"), options: obs.collections)
        case ActionID.obsTransition:
            SuggestField(title: "Transizione", text: s.string("transition"), options: obs.transitions)
        case ActionID.obsHotkey:
            SuggestField(title: "Hotkey", text: s.string("hotkey"), options: obs.hotkeys)
        case ActionID.obsStudioPreview:
            Text("Mostra anteprima e programma in Studio Mode.").foregroundStyle(.secondary)
        case ActionID.twMessage:
            TextField("Messaggio", text: s.string("message"), axis: .vertical)
        case ActionID.twTitle:
            TextField("Titolo della diretta", text: s.string("title"))
            TextField("Gioco/categoria", text: s.string("game"))
        case ActionID.twSlowChat:
            Stepper("Secondi: \(s.wrappedValue.int("seconds", 30))", value: s.int("seconds", 30), in: 3...120)
        case ActionID.spVolUp, ActionID.spVolDown:
            Stepper("Passo: \(s.wrappedValue.int("step", 10)) %", value: s.int("step", 10), in: 1...50)
        case ActionID.mixerDashboard:
            DropdownRowField(title: "Assegna", selection: s.int("mix", 0), options: [(0, "Creator / Master Mix"), (1, "Audience Mix")])
            Toggle("Sincronizza cambio mix", isOn: s.bool("sync", true))
            Toggle("Indicatore di ingresso", isOn: s.bool("input", true))
        case ActionID.dcVoiceChannel, ActionID.dcTextChannel:
            if !discord.isConnected {
                Text("Collega Discord in Impostazioni → Collega app per scegliere server e canale.").foregroundStyle(.secondary)
            }
            let server = s.wrappedValue.string("server")
            DropdownRowField(title: "Server", selection: Binding(get: { server }, set: { s.wrappedValue["server"] = .string($0); s.wrappedValue["channel"] = .string(""); discord.loadChannels($0) }),
                             options: discord.guilds.map { ($0.id, $0.name) } + (server.isEmpty || discord.guilds.contains { $0.id == server } ? [] : [(server, "Server salvato")]))
            let voice = id == ActionID.dcVoiceChannel
            let list = (discord.channels[server] ?? []).filter { $0.voice == voice }
            let channel = s.wrappedValue.string("channel")
            DropdownRowField(title: "Canale", selection: s.string("channel"),
                             options: list.map { ($0.id, (voice ? "🔊 " : "# ") + $0.name) } + (channel.isEmpty || list.contains { $0.id == channel } ? [] : [(channel, "Canale salvato")]))
                .onAppear { discord.loadGuilds(); discord.loadChannels(server) }
        case ActionID.vmVoice:
            if !voicemod.connected { Text("Apri Voicemod e inserisci la API Key in Impostazioni → Collega app.").foregroundStyle(.secondary) }
            let v = s.wrappedValue.string("voice")
            DropdownRowField(title: "Voce", selection: s.string("voice"),
                             options: voicemod.voices.map { ($0.id, $0.name) } + (v.isEmpty || voicemod.voices.contains { $0.id == v } ? [] : [(v, s.wrappedValue.string("voiceName", "Voce salvata"))]))
        case ActionID.vmPlaySound:
            if !voicemod.connected { Text("Apri Voicemod e inserisci la API Key in Impostazioni → Collega app.").foregroundStyle(.secondary) }
            let board = s.wrappedValue.string("board")
            DropdownRowField(title: "Soundboard", selection: Binding(get: { board }, set: { s.wrappedValue["board"] = .string($0); s.wrappedValue["sound"] = .string("") }),
                             options: voicemod.soundboards.map { ($0.name, $0.name) } + (board.isEmpty || voicemod.soundboards.contains { $0.name == board } ? [] : [(board, board)]))
            let sounds = voicemod.soundboards.first { $0.name == board }?.sounds ?? []
            let snd = s.wrappedValue.string("sound")
            DropdownRowField(title: "Suono", selection: s.string("sound"),
                             options: sounds.map { ($0.id, $0.name) } + (snd.isEmpty || sounds.contains { $0.id == snd } ? [] : [(snd, s.wrappedValue.string("soundName", "Suono salvato"))]))
        case ActionID.group:
            Text("Tocca la cartella sul pannello (o doppio clic qui) per aprirla e riempirla.").foregroundStyle(.secondary)
            Button("Apri cartella") { if let p = s.wrappedValue["groupPage"]?.int { engine.deck.enterFolder(p) } }
        default:
            Text("Nessuna impostazione aggiuntiva.").foregroundStyle(.secondary)
        }
    }
}

struct KnobSettingsView: View {
    let actionID: String
    @Binding var settings: Settings
    @EnvironmentObject var engine: ActionEngine
    @EnvironmentObject var obs: OBSClient

    var body: some View {
        Form {
            switch actionID {
            case ActionID.knobInputDevice, ActionID.knobOutputDevice:
                let devs = actionID == ActionID.knobInputDevice ? SystemAudio.inputDevices() : SystemAudio.outputDevices()
                DropdownRowField(title: "Dispositivo", selection: $settings.string("uid"), options: [("", "Predefinito di sistema")] + devs.map { ($0.uid, $0.name) })
            case ActionID.knobOBSVolume:
                SuggestField(title: "Sorgente audio", text: $settings.string("input"), options: obs.inputNames)
            default: EmptyView()
            }
            Stepper("Passo per scatto: \(settings.int("step", 2)) %", value: $settings.int("step", 2), in: 1...20)
            DropdownRowField(title: "Pressione", selection: $settings.string("press", "mute"), options: [("mute", "Muto"), ("none", "Nessuna")])
        }
        .formStyle(.grouped)
        .frame(maxWidth: 480)
    }
}

struct MultiActionEditor: View {
    @Binding var children: [KeyAssignment]

    var body: some View {
        Section("Sequenza di azioni") {
            ForEach($children) { $child in
                DisclosureGroup {
                    ActionSettingsView(key: $child)
                } label: {
                    HStack {
                        Label(ActionCatalog.descriptor(child.actionID).title, systemImage: ActionCatalog.descriptor(child.actionID).symbol)
                        Spacer()
                        Button { children.removeAll { $0.id == child.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
            }
            .onMove { children.move(fromOffsets: $0, toOffset: $1) }
            Menu("Aggiungi azione") {
                ForEach(ActionCatalog.categories) { cat in
                    let items = cat.actions.filter { $0.multiAction && $0.kind == .key }
                    if !items.isEmpty {
                        Menu(cat.title) {
                            ForEach(items) { a in
                                Button(a.title) { children.append(KeyAssignment(actionID: a.id, states: ActionCatalog.defaultStates(for: a))) }
                            }
                        }
                    }
                }
            }
        }
    }
}
