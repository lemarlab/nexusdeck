import SwiftUI
import ServiceManagement

// MARK: Link applications

struct LinkAppsPage: View {
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

struct AccountSheet: View {
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
