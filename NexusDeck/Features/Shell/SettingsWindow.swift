import SwiftUI
import ServiceManagement

struct SettingsWindow: View {
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Impostazioni").font(.system(size: 15, weight: .bold))
                        .padding(.leading, 16).frame(height: 56, alignment: .center)
                    ForEach(SettingsPage.allCases) { p in
                        let on = ui.settingsPage == p
                        Button { ui.settingsPage = p } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 6).fill(p.tint)
                                    .frame(width: 24, height: 24)
                                    .overlay(Image(systemName: p.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
                                Text(p.title).font(.system(size: 13, weight: on ? .medium : .regular)).foregroundStyle(on ? Color.white : Theme.text)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).frame(height: 34)
                            .background(on ? Theme.accent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(width: 244)
                .background(VisualEffect(material: .sidebar))
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        let p = ui.settingsPage ?? .general
                        RoundedRectangle(cornerRadius: 7).fill(p.tint).frame(width: 28, height: 28)
                            .overlay(Image(systemName: p.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
                        Text(p.title).font(.system(size: 17, weight: .bold))
                        Spacer()
                    }
                    .padding(.horizontal, 28).frame(height: 60)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) { page }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack { Spacer(); FlatButton(title: "Fine", prominent: true, width: 90) { dismiss() } }
                        .padding(.horizontal, 20).frame(height: 56)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                }
                .background(Theme.canvas)
            }
        }
        .frame(width: 900, height: 680)
        .background(Theme.settingsBg)
        .foregroundStyle(Theme.text)
        
    }

    @ViewBuilder private var page: some View {
        switch ui.settingsPage ?? .general {
        case .general: GeneralPage()
        case .audioOutput: OutputPage()
        case .obs: OBSPage()
        case .streamlabs: StreamlabsPage()
        case .linkApps: LinkAppsPage()
        case .customLighting: CustomLightingPage()
        case .interactiveLighting: InteractiveLightingPage()
        case .backup: BackupPage()
        case .guide: GuidePage()
        case .feedback: FeedbackPage()
        }
    }
}

/// "Label  [control]  (i)" row used in settings cards.
struct SettingRow<C: View>: View {
    let title: LocalizedStringKey
    var info: String? = nil
    var labelWidth: CGFloat = 92
    @ViewBuilder var content: C
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13))
            if let info { InfoIcon(text: info) }
            Spacer(minLength: 12)
            content
        }
    }
}

struct InfoIcon: View {
    let text: String
    @State private var show = false
    var body: some View {
        Button { show.toggle() } label: { Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Theme.textFaint) }
            .buttonStyle(.plain)
            .popover(isPresented: $show) { Text(text).font(.system(size: 12)).padding(12).frame(width: 260) }
    }
}

/// Ten fixed color swatches used by lighting and background settings.
struct SwatchRow: View {
    @Binding var hex: String
    var first: String = "#FF0000"
    static let colors = ["#FF0000", "#FF8C00", "#00FF00", "#00FF8C", "#00FFFF", "#008CFF", "#0000FF", "#8C00FF", "#FF00FF", "#FF6EFF"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach([first] + Self.colors.dropFirst(first == Self.colors[0] ? 1 : 1).map { $0 }, id: \.self) { c in
                Circle().fill(Color(hex: c)).frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                    .padding(3)
                    .overlay(Circle().strokeBorder(hex.uppercased() == c.uppercased() ? Theme.accent : .clear, lineWidth: 2))
                    .onTapGesture { hex = c }
            }
        }
    }
}

// MARK: General

private struct GeneralPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var devices: DeviceManager
    @EnvironmentObject var bridge: AudioBridge
    @AppStorage("closeMinimizes") private var closeMinimizes = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        SectionCard(title: "Dispositivo") {
            info("Mixer", deviceName)
            info("Account", "Nessun account richiesto")
        }
        SectionCard(title: "Versione software") {
            info("Applicazione", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            info("Firmware", firmware)
            #if DEBUG
            // Test only: simulates an update to the next version (shows the panel animation, the mixer is not touched).
            if firmware != "—" && !DeviceSession.firmwareTestDone {
                HStack {
                    Text("Aggiornamento firmware (test)").font(.system(size: 13))
                    Spacer()
                    Text("Disponibile \(Self.nextVersion(firmware))").font(.system(size: 13)).foregroundStyle(Theme.accent)
                    FlatButton(title: "Aggiorna", prominent: true, width: 100) {
                        DistributedNotificationCenter.default().postNotificationName(Notification.Name("NexusDeck.firmwareDemo"), object: Self.nextVersion(firmware), userInfo: nil, deliverImmediately: true)
                    }
                }
            }
            #endif
            HStack {
                Text("Driver audio").font(.system(size: 13))
                Spacer()
                Text(!bridge.isPlugInInstalled ? "non installato" : bridge.isPlugInOutdated ? "da aggiornare" : "aggiornato")
                    .font(.system(size: 13)).foregroundStyle(bridge.isPlugInOutdated || !bridge.isPlugInInstalled ? Color.orange : Theme.textDim)
                FlatButton(title: !bridge.isPlugInInstalled ? "Installa driver" : bridge.isPlugInOutdated ? "Aggiorna driver" : "Reinstalla driver", width: 140) { _ = bridge.installPlugIn() }
            }
            Text("© 2026 NexusDeck. Non affiliato ad AVerMedia.").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
        }
        SectionCard(title: "Aggiornamenti") {
            UpdateRow()
        }
        SectionCard(title: "Lingua") {
            HStack {
                DarkPicker(selection: .constant("it"), options: [("it", "Italiano"), ("en", "English (United States)")], height: 28).frame(width: 280)
                Spacer()
                FlatButton(title: "Applica", width: 130) {}
            }
        }
        SectionCard(title: "Display del mixer") {
            HStack {
                Text("Animazione cambio pagina sul mixer").font(.system(size: 13))
                InfoIcon(text: "Sperimentale: quando cambi pagina, il display del mixer mostra alcune immagini intermedie della pagina che scorre. Il display aggiorna circa 8 immagini al secondo, quindi l'effetto è a scatti.")
                Spacer()
                PillToggle(isOn: $store.library.device.pageAnimation)
            }
        }
        SectionCard(title: "Impostazioni della finestra") {
            Text("Il pulsante di chiusura (X):").font(.system(size: 13)).foregroundStyle(Theme.textMid)
            HStack(spacing: 60) {
                radio("Riduci a icona", closeMinimizes) { closeMinimizes = true }
                radio("Chiudi applicazione", !closeMinimizes) { closeMinimizes = false }
            }
            HStack(spacing: 10) {
                PillToggle(isOn: Binding(get: { launchAtLogin }, set: { on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; launchAtLogin = on } catch {}
                }))
                Text("Avvia al login").font(.system(size: 13)).foregroundStyle(Theme.textMid)
                Spacer().frame(width: 40)
                if KeySynth.hasAccessibility {
                    Text("Accessibilità concessa").font(.system(size: 12)).foregroundStyle(.green)
                } else {
                    FlatButton(title: "Concedi Accessibilità", width: 170) { KeySynth.requestAccessibility() }
                }
            }
            .padding(.top, 6)
        }
    }

    private var deviceName: String {
        if case .connected(let i) = devices.state { return i.productName }
        return "Nessun dispositivo collegato"
    }

    static func nextVersion(_ v: String) -> String {
        var p = v.split(separator: ".").map { Int($0) ?? 0 }
        if !p.isEmpty { p[p.count - 1] += 1 }
        return p.map(String.init).joined(separator: ".")
    }

    private var firmware: String {
        if case .connected(let i) = devices.state, !i.firmwareVersion.isEmpty { return i.firmwareVersion }
        return "—"
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack(spacing: 20) {
            Text(k).font(.system(size: 13))
            Spacer()
            Text(v).font(.system(size: 13)).foregroundStyle(Theme.textDim)
        }
    }
}

private struct UpdateRow: View {
    @ObservedObject var updater = Updater.shared
    @State private var showNotes = false

    var body: some View {
        HStack(spacing: 12) {
            switch updater.state {
            case .idle: Text("Controlla se è disponibile una nuova versione su GitHub.").foregroundStyle(Theme.textMid)
            case .checking: ProgressView().controlSize(.small); Text("Controllo in corso…").foregroundStyle(Theme.textMid)
            case .upToDate: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("NexusDeck è aggiornato.").foregroundStyle(Theme.textMid)
            case .available(let v): Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent); Text("Disponibile la versione \(v)").bold()
            case .downloading: ProgressView().controlSize(.small); Text("Download in corso…").foregroundStyle(Theme.textMid)
            case .installing: ProgressView().controlSize(.small); Text("Installazione… NexusDeck si riavvierà.").foregroundStyle(Theme.textMid)
            case .failed(let e): Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(e).foregroundStyle(Theme.textMid).lineLimit(2)
            }
            Spacer()
            if case .available = updater.state {
                FlatButton(title: "Novità e aggiorna…", width: 170) { showNotes = true }
            } else {
                FlatButton(title: "Controlla aggiornamenti", width: 190) { Task { await updater.check(); if updater.latestVersion != nil { showNotes = true } } }
                    .disabled(updater.state == .checking || updater.state == .downloading || updater.state == .installing)
            }
        }
        .font(.system(size: 13))
        HStack(spacing: 12) {
            Text("Controllo automatico:").font(.system(size: 13)).foregroundStyle(Theme.textMid)
            DarkPicker(selection: $updater.frequency, options: Updater.Frequency.allCases.map { ($0, $0.title) }, height: 26).frame(width: 200)
            Spacer()
        }
        .sheet(isPresented: $showNotes) { UpdateSheet() }
    }
}

func radio(_ title: LocalizedStringKey, _ on: Bool, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 14) {
            Circle().fill(Theme.field).overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1)).frame(width: 16, height: 16)
                .overlay(Circle().fill(Theme.accent).frame(width: 6, height: 6).opacity(on ? 1 : 0))
            Text(title).font(.system(size: 13)).foregroundStyle(Theme.textMid)
        }
    }
    .buttonStyle(.plain)
}

// MARK: Audio output

private struct OutputPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var bridge: AudioBridge

    var body: some View {
        SectionCard(title: "Mixer audio") {
            SettingRow(title: "Frequenza", labelWidth: 110) {
                DarkPicker(selection: Binding(get: { store.library.device.sampleRate }, set: { rate in
                    store.library.device.sampleRate = rate
                    bridge.setSampleRate(Double(rate))
                }), options: [(48000, "24 bit, 48000 Hz"), (96000, "24 bit, 96000 Hz")], height: 24).frame(width: 280)
            }
        }
        SectionCard(title: "Line Out") {
            SettingRow(title: "Sorgente", labelWidth: 110) {
                DarkPicker(selection: Binding(get: { store.library.device.lineOutSource }, set: { store.library.device.lineOutSource = $0; audio.applyDevice() }),
                           options: [(0, "Creator Mix"), (1, "Audience Mix"), (2, "Chat Mic")]).frame(width: 280)
            }
        }
        SectionCard(title: "Chat Mic") {
            SettingRow(title: "Sorgente", labelWidth: 110) {
                DarkPicker(selection: Binding(get: { store.library.device.chatMicWithEffects }, set: { store.library.device.chatMicWithEffects = $0; audio.applyDSP() }),
                           options: [(true, "Mic con effetti"), (false, "Mic senza effetti")]).frame(width: 280)
            }
        }
        SectionCard(title: "Volume cuffie / Line Out") {
            volume("Cuffie", \.headphonesVolume)
            volume("Line Out", \.lineOutVolume)
        }
    }

    private func volume(_ t: LocalizedStringKey, _ kp: WritableKeyPath<DeviceSettings, Int>) -> some View {
        SettingRow(title: t, labelWidth: 110) {
            ThinSlider(value: Binding(get: { Double(store.library.device[keyPath: kp]) }, set: { store.library.device[keyPath: kp] = Int($0) })) { audio.applyDevice() }
                .frame(width: 220)
            Text("\(store.library.device[keyPath: kp])%").font(.system(size: 13)).foregroundStyle(Theme.textMid).padding(.leading, 20)
        }
    }
}

// MARK: OBS / Streamlabs

private struct OBSPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var obs: OBSClient
    @State private var password = Keychain.get("obs") ?? ""
    @State private var reveal = false

    var body: some View {
        SectionCard(title: "Impostazioni server WebSocket di OBS") {
            VStack(alignment: .leading, spacing: 6) {
                label("Indirizzo IP")
                HStack(spacing: 14) {
                    TextField("", text: Binding(get: { store.library.integrations.obsHost == "127.0.0.1" ? "Localhost (questo computer)" : store.library.integrations.obsHost },
                                                set: { store.library.integrations.obsHost = $0.hasPrefix("Localhost") ? "127.0.0.1" : $0 }))
                        .darkField(height: 26).frame(width: 384)
                    InfoIcon(text: "Indirizzo del computer su cui gira OBS. Usa Localhost se è questo Mac.")
                }
                label("Porta del server").padding(.top, 8)
                HStack(spacing: 14) {
                    TextField("", value: $store.library.integrations.obsPort, format: .number.grouping(.never)).darkField(height: 26).frame(width: 384)
                    InfoIcon(text: "Porta del server WebSocket di OBS (predefinita 4455).")
                }
                label("Password").padding(.top, 8)
                HStack(spacing: 14) {
                    ZStack(alignment: .trailing) {
                        Group { if reveal { TextField("", text: $password) } else { SecureField("", text: $password) } }.darkField(height: 26)
                        Button { reveal.toggle() } label: { Image(systemName: "eye.fill").foregroundStyle(Theme.textMid) }.buttonStyle(.plain).padding(.trailing, 8)
                    }
                    .frame(width: 384)
                    InfoIcon(text: "Lascia vuoto se in OBS l'autenticazione è disattivata.")
                }
                HStack(spacing: 14) {
                    FlatButton(title: "Applica", width: 134) {
                        Keychain.set(password, for: "obs")
                        obs.configure(host: store.library.integrations.obsHost, port: store.library.integrations.obsPort, password: password)
                        obs.connect()
                    }
                    Circle().fill(obs.isConnected ? Color.green : Color.gray).frame(width: 8, height: 8)
                    Text(statusText).font(.system(size: 12)).foregroundStyle(Theme.textDim)
                }
                .padding(.top, 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggerimento:")
                    Text("OBS 28 e successivi includono già il server WebSocket (Strumenti → Impostazioni server WebSocket).")
                    HStack(spacing: 0) {
                        Text("Per OBS 27 installa ")
                        Link("obs-websocket 5", destination: URL(string: "https://github.com/obsproject/obs-websocket/releases")!).foregroundStyle(Color(hex: "#3BA3FF"))
                        Text(".")
                    }
                }
                .font(.system(size: 13)).foregroundStyle(Theme.textMid).padding(.top, 60).padding(.bottom, 30)
            }
        }
        .frame(width: 526)
    }

    private func label(_ t: LocalizedStringKey) -> some View { Text(t).font(.system(size: 13.5)).foregroundStyle(Theme.textMid) }

    private var statusText: String {
        switch obs.status {
        case .connected: "Connesso"
        case .connecting: "Connessione…"
        case .disconnected: "Non connesso"
        case .failed(let e): e
        }
    }
}

private struct StreamlabsPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var streamlabs: StreamlabsClient
    @State private var token = Keychain.get("streamlabs") ?? ""

    var body: some View {
        SectionCard(title: "Token API di Streamlabs Desktop") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Token API di Streamlabs Desktop").font(.system(size: 13.5)).foregroundStyle(Theme.textMid)
                HStack(spacing: 14) {
                    SecureField("", text: $token).darkField(height: 26).frame(width: 384)
                    InfoIcon(text: "Streamlabs Desktop → Impostazioni → Controllo remoto → mostra dettagli → token API.")
                }
                Text("Porta").font(.system(size: 13.5)).foregroundStyle(Theme.textMid).padding(.top, 8)
                TextField("", value: $store.library.integrations.streamlabsPort, format: .number.grouping(.never)).darkField(height: 26).frame(width: 384)
                HStack(spacing: 14) {
                    FlatButton(title: "Applica", width: 134) {
                        Keychain.set(token, for: "streamlabs")
                        store.library.integrations.streamlabsEnabled = true
                        streamlabs.connect(port: store.library.integrations.streamlabsPort, token: token)
                    }
                    .disabled(token.isEmpty)
                    if streamlabs.connected { Text("Connesso").font(.system(size: 12)).foregroundStyle(.green) }
                }
                .padding(.top, 10)
            }
        }
    }
}

// MARK: Link applications

private struct LinkAppsPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var twitch: TwitchClient
    @EnvironmentObject var youtube: YouTubeClient
    @EnvironmentObject var spotify: SpotifyClient
    @State private var configuring: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Gestione account social").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textMid)
                Spacer()
                InfoIcon(text: "Collega i tuoi account per usare i widget di YouTube, Twitch e Spotify. Ogni servizio richiede un Client ID registrato da te.")
            }
            HStack(spacing: 50) {
                account("YouTube", Color(hex: "#FF0000"), "play.rectangle.fill", youtube.isLoggedIn, youtube.channelTitle) { configuring = "youtube" }
                account("Twitch", Color(hex: "#9146FF"), "bubble.left.fill", twitch.isLoggedIn, twitch.userName) { configuring = "twitch" }
                account("Spotify", Color(hex: "#1ED760"), "music.note", spotify.isLoggedIn, "Spotify") { configuring = "spotify" }
            }
            .padding(.top, 26).padding(.leading, 50)
            BuiltInIntegrationsSettings()
                .padding(.top, 30).padding(.leading, 50).padding(.trailing, 30)
            Spacer()
            if !(youtube.isLoggedIn || twitch.isLoggedIn || spotify.isLoggedIn) {
                Text("Clicca Aggiungi account per accedere o aggiungere un nuovo account.")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textMid).frame(maxWidth: .infinity)
            }
            Spacer()
        }
        .padding(20)
        .frame(height: 612)
        .background(Theme.card)
        .sheet(item: Binding(get: { configuring.map { IdentifiedString(value: $0) } }, set: { configuring = $0?.value })) { s in
            AccountSheet(service: s.value)
        }
    }

    private func account(_ name: String, _ color: Color, _ symbol: String, _ on: Bool, _ who: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.white)
                    .frame(width: 32, height: 22).background(color).clipShape(RoundedRectangle(cornerRadius: 5))
                Text(on ? who : "Aggiungi account").font(.system(size: 14)).foregroundStyle(Theme.textMid)
            }
        }
        .buttonStyle(.plain)
    }
}

struct IdentifiedString: Identifiable { let value: String; var id: String { value } }

private struct AccountSheet: View {
    let service: String
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var twitch: TwitchClient
    @EnvironmentObject var youtube: YouTubeClient
    @EnvironmentObject var spotify: SpotifyClient
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(service.capitalized).font(.system(size: 15, weight: .bold))
            switch service {
            case "twitch":
                field("Client ID (dev.twitch.tv)", $store.library.integrations.twitchClientID)
                status(twitch.isLoggedIn, twitch.userName, twitch.pendingCode, twitch.lastError)
                buttons(twitch.isLoggedIn, login: { twitch.clientID = store.library.integrations.twitchClientID; Task { await twitch.login() } }, logout: twitch.logout)
            case "youtube":
                field("Client ID (Google Cloud, tipo TV)", $store.library.integrations.youtubeClientID)
                field("Client secret", $store.library.integrations.youtubeClientSecret)
                status(youtube.isLoggedIn, youtube.channelTitle, youtube.pendingCode, youtube.lastError)
                buttons(youtube.isLoggedIn, login: {
                    youtube.clientID = store.library.integrations.youtubeClientID
                    youtube.clientSecret = store.library.integrations.youtubeClientSecret
                    Task { await youtube.login() }
                }, logout: youtube.logout)
            default:
                field("Client ID (developer.spotify.com)", $store.library.integrations.spotifyClientID)
                Text("Redirect URI: http://127.0.0.1:17564/callback").font(.system(size: 11)).foregroundStyle(Theme.textDim).textSelection(.enabled)
                status(spotify.isLoggedIn, "Collegato", nil, spotify.lastError)
                buttons(spotify.isLoggedIn, login: { spotify.clientID = store.library.integrations.spotifyClientID; Task { await spotify.login() } }, logout: spotify.logout)
            }
            HStack { Spacer(); FlatButton(title: "Fine", prominent: true, width: 90) { dismiss() } }
        }
        .padding(20).frame(width: 460)
        .background(Theme.panel)
    }

    private func field(_ t: String, _ b: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.system(size: 12)).foregroundStyle(Theme.textMid)
            TextField("", text: b).darkField(height: 26)
        }
    }

    @ViewBuilder private func status(_ ok: Bool, _ name: String, _ code: (code: String, url: URL)?, _ error: String?) -> some View {
        HStack { Circle().fill(ok ? Color.green : Color.gray).frame(width: 8, height: 8); Text(ok ? name : "Non collegato").font(.system(size: 12)) }
        if let code {
            HStack {
                Text("Codice:").font(.system(size: 12))
                Text(code.code).font(.system(size: 15, weight: .bold, design: .monospaced)).textSelection(.enabled)
                Link("apri \(code.url.host ?? "")", destination: code.url).font(.system(size: 12))
            }
        }
        if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
    }

    private func buttons(_ ok: Bool, login: @escaping () -> Void, logout: @escaping () -> Void) -> some View {
        HStack { if ok { FlatButton(title: "Esci", width: 110, action: logout) } else { FlatButton(title: "Accedi", prominent: true, width: 110, action: login) } }
    }
}

// MARK: Custom lighting

private enum LightingArea: String { case screen, keys, knobs, strip }

private struct CustomLightingPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var deck: DeckController
    @State private var area: LightingArea = .screen

    private func dev<T>(_ kp: WritableKeyPath<DeviceSettings, T>, _ apply: @escaping () -> Void = {}) -> Binding<T> {
        Binding(get: { store.library.device[keyPath: kp] }, set: { store.library.device[keyPath: kp] = $0; apply() })
    }

    var body: some View {
        LightingDeviceDrawing(area: $area, stripHex: store.library.device.ledAura.colorHex, knobHex: store.library.device.ledKnob.colorSource == .perItem ? store.library.device.ledKnob.itemColors[0] : store.library.device.ledKnob.colorHex)
            .frame(maxWidth: .infinity).padding(.bottom, 10)
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textMid)
                Spacer()
                Button { reset() } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.plain).foregroundStyle(Theme.textDim)
            }
            switch area {
            case .screen: screenSettings
            case .keys: LEDControls(led: dev(\.ledButton, { audio.applyLEDs() }), zone: .keys)
            case .knobs: LEDControls(led: dev(\.ledKnob, { audio.applyLEDs() }), zone: .knobs)
            case .strip: LEDControls(led: dev(\.ledAura, { audio.applyLEDs() }), zone: .strip)
            }
        }
        .padding(.horizontal, 40).padding(.vertical, 18)
        .background(Theme.card)
    }

    private var title: LocalizedStringKey {
        switch area {
        case .screen: "Schermo touch"
        case .keys: "Tasti funzione"
        case .knobs: "Manopole"
        case .strip: "Luce ambiente"
        }
    }

    @ViewBuilder private var screenSettings: some View {
        SettingRow(title: "Spegni dopo", info: "Lo schermo si spegne dopo questo tempo di inattività. Toccalo per riaccenderlo.", labelWidth: 150) {
            DarkPicker(selection: dev(\.powerSavingMinutes, { audio.applyScreen() }),
                       options: [(0, "Mai"), (1, "1 minuto"), (5, "5 minuti"), (10, "10 minuti"), (20, "20 minuti"), (30, "30 minuti"), (60, "1 ora")], height: 26).frame(width: 312)
        }
        SettingRow(title: "Luminosità", labelWidth: 150) {
            Image(systemName: "sun.min").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            ThinSlider(value: Binding(get: { Double(store.library.device.brightness) }, set: { store.library.device.brightness = Int($0) }), range: 1...100) { audio.applyScreen() }
                .frame(width: 236)
            Image(systemName: "sun.max").font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        SettingRow(title: "Opacità tasti", info: "Trasparenza dei tasti sopra lo sfondo dello schermo.", labelWidth: 150) {
            Image(systemName: "circle.dotted").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            ThinSlider(value: Binding(get: { store.library.device.panelOpacity * 100 }, set: { store.library.device.panelOpacity = $0 / 100; deck.needsRedraw.send() }))
                .frame(width: 236)
            Image(systemName: "circle.fill").font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        SettingRow(title: "Griglia", labelWidth: 150) {
            Toggle("Nascondi la griglia delle caselle vuote", isOn: dev(\.autoHideGrid, { deck.needsRedraw.send() }))
                .toggleStyle(.checkbox).font(.system(size: 13)).fixedSize()
        }
        SettingRow(title: "Effetti al tocco", labelWidth: 150) {
            Toggle("Rimpicciolisci il tasto quando lo tocchi", isOn: dev(\.touchEffect)).toggleStyle(.checkbox).font(.system(size: 13)).fixedSize()
        }
        SettingRow(title: "Sfondo", labelWidth: 150) {
            DarkPicker(selection: dev(\.background.mode, { deck.needsRedraw.send() }), options: [(.color, "Colore pieno"), (.image, "Immagine")], height: 26).frame(width: 312)
        }
        if store.library.device.background.mode == .color {
            SettingRow(title: "", labelWidth: 150) {
                SwatchRow(hex: Binding(get: { store.library.device.background.colorHex }, set: { store.library.device.background.colorHex = $0; deck.needsRedraw.send() }), first: "#111111")
            }
        } else {
            SettingRow(title: "Adattamento", labelWidth: 150) {
                DarkPicker(selection: dev(\.background.displayMode, { deck.needsRedraw.send() }), options: BackgroundSetting.displayModes, height: 26).frame(width: 312)
            }
            SettingRow(title: "", labelWidth: 150) {
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { i in
                        let recent = store.library.device.background.recent
                        let path = i < recent.count ? recent[i] : ""
                        Button {
                            if path.isEmpty { pickBackground() } else { store.library.device.background.use(path); deck.needsRedraw.send() }
                        } label: {
                            ZStack {
                                Theme.field
                                if let img = NSImage(contentsOfFile: path) { Image(nsImage: img).resizable().scaledToFill() }
                                else { Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(Theme.textDim) }
                            }
                            .frame(width: 50, height: 30).clipped()
                            .overlay(Rectangle().strokeBorder(path == store.library.device.background.imagePath && !path.isEmpty ? Theme.accent : Color.white.opacity(0.12), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            SettingRow(title: "", labelWidth: 150) {
                FlatButton(title: "Scegli immagine…", width: 150) { pickBackground() }
                Text("800 × 480 px · PNG, JPG").font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
        }
    }

    private func pickBackground() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg]
        guard p.runModal() == .OK, let u = p.url else { return }
        let dst = ProfileStore.iconFolder.appendingPathComponent("background-\(UUID().uuidString.prefix(8))." + u.pathExtension)
        try? FileManager.default.copyItem(at: u, to: dst)
        store.library.device.background.use(dst.path)
        deck.needsRedraw.send()
    }

    private func reset() {
        let d = DeviceSettings()
        switch area {
        case .screen:
            store.library.device.brightness = d.brightness; store.library.device.powerSavingMinutes = d.powerSavingMinutes
            store.library.device.panelOpacity = d.panelOpacity; store.library.device.autoHideGrid = d.autoHideGrid
            store.library.device.touchEffect = d.touchEffect; store.library.device.background = d.background
            audio.applyScreen(); deck.needsRedraw.send()
        case .keys: store.library.device.ledButton = d.ledButton; audio.applyLEDs()
        case .knobs: store.library.device.ledKnob = d.ledKnob; audio.applyLEDs()
        case .strip: store.library.device.ledAura = d.ledAura; audio.applyLEDs()
        }
    }
}

/// Lighting controls for one zone, always in the same order:
/// Effect → Brightness → Speed (animated effects) → Color (effects that use one, with a per-zone color source).
struct LEDControls: View {
    enum Zone { case keys, knobs, strip, status }

    @Binding var led: LEDSetting
    let zone: Zone
    @State private var editing = 0

    private var modes: [LEDSetting.Mode] {
        switch zone {
        case .keys: [.off, .staticColor]
        case .knobs: [.off, .staticColor, .flash, .rainbow, .volume]
        case .strip: [.off, .staticColor, .flash, .rainbow, .wave, .colorCycle, .spectrum]
        case .status: [.staticColor, .flash, .rainbow]
        }
    }

    private var sources: [(LEDSetting.ColorSource, String)] {
        switch zone {
        case .keys: [(.widget, "Colore del widget"), (.single, "Uguale per tutti"), (.perItem, "Diverso per ogni tasto")]
        case .knobs: [(.single, "Uguale per tutte"), (.perItem, "Diverso per ogni manopola")]
        default: []
        }
    }

    private var itemNames: [String] {
        zone == .keys ? ["Alto sx", "Alto dx", "Basso sx", "Basso dx"] : ["Mic", "Line In", "Console", "System", "Game", "Chat"]
    }

    /// Color source actually used by this zone.
    private var source: LEDSetting.ColorSource {
        sources.contains { $0.0 == led.colorSource } ? led.colorSource : .single
    }

    var body: some View {
        SettingRow(title: "Effetto", labelWidth: 150) {
            DarkPicker(selection: $led.mode, options: modes.map { ($0, title($0)) }, height: 26).frame(width: 312)
        }
        if led.mode != .off {
            SettingRow(title: "Luminosità", labelWidth: 150) {
                Image(systemName: "sun.min").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                ThinSlider(value: Binding(get: { Double(led.brightness) }, set: { led.brightness = Int($0) })).frame(width: 236)
                Image(systemName: "sun.max").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
        }
        if led.mode.usesSpeed {
            SettingRow(title: "Velocità", labelWidth: 150) {
                Image(systemName: "tortoise").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                ThinSlider(value: Binding(get: { Double(led.speed) }, set: { led.speed = Int($0) }), range: 0...10).frame(width: 236)
                Image(systemName: "hare").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
        }
        if led.mode == .volume {
            SettingRow(title: "Misuratore di picco", info: "Gli anelli mostrano il livello audio in tempo reale invece del volume impostato.", labelWidth: 150) {
                Toggle("Attivo", isOn: $led.peak).toggleStyle(.checkbox).font(.system(size: 13))
            }
        }
        if led.mode.usesColor {
            colorSection
        } else if led.mode != .off {
            SettingRow(title: "Colore", labelWidth: 150) {
                Text("Questo effetto usa colori automatici.").font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
        }
    }

    @ViewBuilder private var colorSection: some View {
        if !sources.isEmpty {
            SettingRow(title: "Colore", labelWidth: 150) {
                DarkPicker(selection: Binding(get: { source }, set: { led.colorSource = $0 }), options: sources, height: 26).frame(width: 312)
            }
        }
        switch source {
        case .widget:
            SettingRow(title: "", labelWidth: 150) {
                Text("Ogni tasto prende il colore di sfondo del widget assegnato. I tasti vuoti restano spenti.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textDim).frame(width: 312, alignment: .leading)
            }
        case .single:
            SettingRow(title: sources.isEmpty ? "Colore" : "", labelWidth: 150) { SwatchRow(hex: $led.colorHex) }
        case .perItem:
            SettingRow(title: "", labelWidth: 150) {
                HStack(spacing: 8) {
                    ForEach(itemNames.indices, id: \.self) { i in
                        VStack(spacing: 4) {
                            Circle().fill(Color(hex: led.itemColors[i])).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(editing == i ? Theme.accent : Color.white.opacity(0.25), lineWidth: editing == i ? 2 : 1))
                            Text(itemNames[i]).font(.system(size: 10)).foregroundStyle(editing == i ? Theme.text : Theme.textDim)
                        }
                        .frame(width: 50)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = i }
                    }
                    ColorPicker("", selection: Binding(get: { Color(hex: led.itemColors[editing]) }, set: { led.itemColors[editing] = $0.hex }), supportsOpacity: false)
                        .labelsHidden()
                }
            }
            SettingRow(title: "", labelWidth: 150) {
                SwatchRow(hex: Binding(get: { led.itemColors[min(editing, itemNames.count - 1)] }, set: { led.itemColors[min(editing, itemNames.count - 1)] = $0 }))
            }
        }
    }

    private func title(_ m: LEDSetting.Mode) -> String {
        switch m {
        case .off: "Spento"
        case .staticColor: zone == .keys ? "Acceso" : "Statico"
        case .breathing: "Statico"
        case .flash: "Pulsante"
        case .rainbow: "Respiro"
        case .wave: "Arcobaleno"
        case .colorCycle: "Ciclo colori"
        case .spectrum: "Onda colori"
        case .volume: "Livello volume"
        }
    }
}

private struct LightingDeviceDrawing: View {
    @Binding var area: LightingArea
    let stripHex: String
    let knobHex: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#3A3A3A")).frame(width: 414, height: 270)
                Text("NexusDeck").font(.system(size: 12, weight: .heavy)).italic().offset(x: 320, y: 16)
                // Screen
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(hex: "#2A2A2A"))
                    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                        ForEach(0..<4, id: \.self) { _ in GridRow { ForEach(0..<5, id: \.self) { _ in Rectangle().fill(Color(hex: "#1E1E1E")) } } }
                    }
                    .padding(22)
                }
                .frame(width: 240, height: 162)
                .overlay(corners(area == .screen))
                .offset(x: 10, y: 30)
                .onTapGesture { area = .screen }
                // Keys
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(0..<2, id: \.self) { _ in GridRow { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 6).fill(Color.black).frame(width: 50, height: 62) } } }
                }
                .padding(10)
                .overlay(corners(area == .keys))
                .offset(x: 272, y: 38)
                .onTapGesture { area = .keys }
                // Knobs
                HStack(spacing: 18) {
                    ForEach(0..<6, id: \.self) { _ in
                        Circle().fill(Color(hex: "#1A1A1A")).frame(width: 50, height: 50)
                            .overlay(Circle().strokeBorder(Color(hex: knobHex), style: StrokeStyle(lineWidth: 3, dash: [5, 3])).padding(2))
                    }
                }
                .padding(6)
                .overlay(corners(area == .knobs))
                .offset(x: 10, y: 205)
                .onTapGesture { area = .knobs }
            }
            .frame(width: 414, height: 270)
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#2E2E2E")).frame(width: 420, height: 40)
                Rectangle().fill(area == .strip ? AnyShapeStyle(Color(hex: stripHex))
                                 : AnyShapeStyle(LinearGradient(colors: [.green, .cyan, .blue, .purple, .pink, .red, .orange, .yellow, .green], startPoint: .leading, endPoint: .trailing)))
                    .frame(width: 420, height: 3).offset(y: 2)
            }
            .overlay(HStack { Rectangle().fill(area == .strip ? Theme.accent : Color(hex: "#555")).frame(width: 2, height: 46); Spacer(); Rectangle().fill(area == .strip ? Theme.accent : Color(hex: "#555")).frame(width: 2, height: 46) }.frame(width: 446))
            .padding(.top, 20)
            .onTapGesture { area = .strip }
        }
    }

    private func corners(_ on: Bool) -> some View {
        GeometryReader { g in
            let c = on ? Theme.accent : Color(hex: "#555555")
            Path { p in
                let w = g.size.width, h = g.size.height, l: CGFloat = 10
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: 0, y: h - l)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: l, y: h))
                p.move(to: CGPoint(x: w - l, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - l))
            }
            .stroke(c, lineWidth: 3)
        }
    }
}

// MARK: Interactive lighting

private struct InteractiveLightingPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var engine: ActionEngine

    private func dev<T>(_ kp: WritableKeyPath<DeviceSettings, T>) -> Binding<T> {
        Binding(get: { store.library.device[keyPath: kp] }, set: { store.library.device[keyPath: kp] = $0; engine.syncStates() })
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#2E2E2E")).frame(width: 420, height: 40)
            Rectangle().fill(Color(hex: store.library.device.streamFirst ? store.library.device.ledStream.colorHex : store.library.device.ledRecord.colorHex))
                .frame(width: 420, height: 3).offset(y: 2)
        }
        .overlay(HStack { Rectangle().fill(Theme.accent).frame(width: 2, height: 46); Spacer(); Rectangle().fill(Theme.accent).frame(width: 2, height: 46) }.frame(width: 446))
        .frame(maxWidth: .infinity).padding(.vertical, 30)
        HStack(spacing: 10) {
            PillToggle(isOn: dev(\.interactiveLighting))
            Text("Effetto interattivo").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textMid)
            InfoIcon(text: "Durante una diretta o una registrazione (OBS / Streamlabs) la luce ambiente cambia per segnalarlo.")
        }
        .padding(.leading, 22)
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 60) {
                radio("Diretta", store.library.device.streamFirst) { store.library.device.streamFirst = true }
                radio("Registrazione", !store.library.device.streamFirst) { store.library.device.streamFirst = false }
            }
            .padding(.leading, 22)
            lightCard("Luce diretta", "dot.radiowaves.left.and.right", dev(\.ledStream), selected: store.library.device.streamFirst)
            lightCard("Luce registrazione", "record.circle", dev(\.ledRecord), selected: !store.library.device.streamFirst)
        }
        .padding(.vertical, 20)
        .background(Theme.card)
        .opacity(store.library.device.interactiveLighting ? 1 : 0.5)
        .allowsHitTesting(store.library.device.interactiveLighting)
    }

    private func lightCard(_ t: LocalizedStringKey, _ symbol: String, _ led: Binding<LEDSetting>, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(Theme.textMid)
                Text(t).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textMid)
                Spacer()
                Button { led.wrappedValue = t == "Luce diretta" ? DeviceSettings().ledStream : DeviceSettings().ledRecord } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textDim)
            }
            LEDControls(led: led, zone: .status)
        }
        .padding(.horizontal, 40).padding(.vertical, 22)
        .background(Theme.card)
        .overlay(alignment: .leading) { if selected { Rectangle().fill(Theme.accent).frame(width: 3) } }
        .padding(.horizontal, 20)
    }
}

// MARK: Backup

private struct BackupPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var audio: AudioService
    @State private var selected = 0
    @State private var message: String?

    var body: some View {
        SectionCard(title: "Backup e ripristino del file di configurazione") {
            Text("Salva la configurazione di NexusDeck su questo Mac per poterla ripristinare in futuro.").font(.system(size: 13)).foregroundStyle(Theme.textMid)
            Text(message ?? lastBackupText).font(.system(size: 13)).foregroundStyle(Theme.textMid)
            HStack(spacing: 12) {
                FlatButton(title: "Esegui backup", width: 134) { do { try store.backupSlot(selected); message = "Backup salvato nello slot \(selected + 1)" } catch { message = error.localizedDescription } }
                FlatButton(title: "Ripristina backup", width: 134) {
                    do { try store.restoreSlot(selected); deck.profileChanged(); audio.applyAll(); message = "Configurazione ripristinata" } catch { message = "Lo slot selezionato è vuoto" }
                }
                .disabled(store.slotDate(selected) == nil)
            }
            Text("Seleziona prima lo slot da salvare o ripristinare").font(.system(size: 13)).foregroundStyle(Theme.textMid)
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    Button { selected = i } label: {
                        HStack(spacing: 24) {
                            Image(systemName: "square.grid.2x2").font(.system(size: 15))
                            Text(store.slotDate(i).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Nessuna data")
                                .font(.system(size: 14))
                                .foregroundStyle(selected == i ? Theme.accent : Theme.textMid)
                            Spacer()
                        }
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(Theme.field).clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var lastBackupText: String {
        let dates = (0..<5).compactMap { store.slotDate($0) }
        guard let last = dates.max() else { return "Nessun backup salvato su questo Mac" }
        return "Ultimo backup: \(last.formatted(date: .abbreviated, time: .shortened))"
    }
}

// MARK: Guide / Feedback

private struct GuidePage: View {
    @EnvironmentObject var store: ProfileStore
    private let items = ["Organizza il pannello di controllo", "Personalizza i widget", "Controlli a due stati", "Impostazioni microfono", "Effetti microfono",
                         "Prova il Dual Mix", "Barra laterale", "Tabella di routing audio", "Dimensioni della finestra", "Modifica del testo",
                         "Installazione dei widget", "Profilo tasti consigliato"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlatButton(title: "Riproduci tutto", width: 130) { store.library.tutorialDone = false }
            HStack {
                Text("Elenco guide").font(.system(size: 14)).foregroundStyle(Theme.textDim)
                Spacer()
                Text("Riproduci").font(.system(size: 14)).foregroundStyle(Theme.textDim).frame(width: 120)
            }
            .padding(.top, 30).padding(.bottom, 20)
            ForEach(items, id: \.self) { t in
                HStack {
                    Text(t).font(.system(size: 13.5)).foregroundStyle(Theme.textMid)
                    Spacer()
                    Button { store.library.tutorialDone = false } label: { Image(systemName: "play.circle").font(.system(size: 16)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.textDim).frame(width: 120)
                }
                .frame(height: 40)
            }
        }
        .padding(20)
        .background(Theme.card)
    }
}

private struct FeedbackPage: View {
    @EnvironmentObject var devices: DeviceManager
    @State private var text = ""
    @State private var copied = false

    var body: some View {
        SectionCard(title: "Aiuto e suggerimenti") {
            Text("Descrivi il problema o il suggerimento. Le informazioni di sistema vengono aggiunte al testo copiato.")
                .font(.system(size: 13)).foregroundStyle(Theme.textMid)
            TextEditor(text: $text).font(.system(size: 13)).scrollContentBackground(.hidden).background(Theme.field).frame(height: 180)
            HStack {
                FlatButton(title: "Copia negli appunti", width: 170) {
                    var info = "NexusDeck \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
                    if case .connected(let d) = devices.state { info += "\(d.productName) firmware \(d.firmwareVersion)\n" }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(info + "\n" + text, forType: .string)
                    copied = true
                }
                if copied { Text("Copiato").font(.system(size: 12)).foregroundStyle(.green) }
            }
        }
    }
}

// MARK: Discord / Voicemod

/// Credentials of the integrations built into NexusDeck (shown when they are switched on in the store).
struct BuiltInIntegrationsSettings: View {
    @EnvironmentObject var engine: ActionEngine
    @EnvironmentObject var discord: DiscordClient
    @EnvironmentObject var voicemod: VoicemodClient
    @AppStorage(BuiltInIntegration.discord.defaultsKey) private var discordOn = false
    @AppStorage(BuiltInIntegration.voicemod.defaultsKey) private var voicemodOn = false
    @State private var clientID = Keychain.get("discord.clientID") ?? ""
    @State private var secret = Keychain.get("discord.clientSecret") ?? ""
    @State private var apiKey = Keychain.get("voicemod.apiKey") ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if discordOn { discordSection }
            if voicemodOn { voicemodSection }
            if !discordOn && !voicemodOn {
                Text("Discord e Voicemod si attivano dal Widget Store, nella sezione Integrazioni.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
        }
    }

    private var discordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Discord", BuiltInIntegration.discord, status: discordStatus, ok: discord.isConnected)
            Text("Crea un'applicazione nel portale sviluppatori di Discord, aggiungi http://localhost come Redirect, poi copia qui Client ID e Client Secret. Al primo collegamento Discord chiede di autorizzare NexusDeck.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Client ID", text: $clientID).darkField(height: 26).frame(width: 190)
                SecureField("Client Secret", text: $secret).darkField(height: 26).frame(width: 190)
            }
            HStack(spacing: 10) {
                FlatButton(title: discord.isConnected ? "Ricollega" : "Collega", width: 100) { discord.configure(clientID: clientID, secret: secret) }
                if discord.isConnected { FlatButton(title: "Scollega", width: 100) { discord.signOut() } }
                Button("Portale sviluppatori") { NSWorkspace.shared.open(URL(string: "https://discord.com/developers/applications")!) }
                    .buttonStyle(.link).font(.system(size: 12))
            }
        }
    }

    private var voicemodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Voicemod", BuiltInIntegration.voicemod, status: voicemod.connected ? "Connesso" : (voicemod.lastError ?? "Non connesso"), ok: voicemod.connected)
            Text("Serve Voicemod aperto e una API Key personale gratuita, che Voicemod invia per email.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
            HStack(spacing: 10) {
                SecureField("API Key", text: $apiKey).darkField(height: 26).frame(width: 260)
                FlatButton(title: "Salva", width: 80) { voicemod.apiKey = apiKey; voicemod.reconnect() }
                Button("Richiedi una chiave") { NSWorkspace.shared.open(URL(string: "https://voicemod.typeform.com/to/Zh5ZHRED")!) }
                    .buttonStyle(.link).font(.system(size: 12))
            }
        }
    }

    private var discordStatus: String {
        switch discord.status {
        case .off: "Non collegato"
        case .connecting: "Connessione…"
        case .connected: discord.account.isEmpty ? "Connesso" : "Connesso come \(discord.account)"
        case .failed(let e): e
        }
    }

    private func header(_ t: String, _ i: BuiltInIntegration, status: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: i.symbol).font(.system(size: 12)).foregroundStyle(.white)
                .frame(width: 32, height: 22).background(Color(hex: i.color)).clipShape(RoundedRectangle(cornerRadius: 5))
            Text(t).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textMid)
            Circle().fill(ok ? Color.green : Color.gray).frame(width: 8, height: 8)
            Text(status).font(.system(size: 12)).foregroundStyle(Theme.textDim)
        }
    }
}
