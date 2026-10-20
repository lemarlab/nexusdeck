import SwiftUI
import ServiceManagement

// MARK: OBS / Streamlabs

struct OBSPage: View {
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

struct StreamlabsPage: View {
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
