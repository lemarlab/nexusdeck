import SwiftUI
import ServiceManagement

// MARK: Link applications

struct IdentifiedString: Identifiable { let value: String; var id: String { value } }

struct AccountSheet: View {
    let service: String
    /// Shown inside the Integrations page (no title, no Done button).
    var embedded = false
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var twitch: TwitchClient
    @EnvironmentObject var youtube: YouTubeClient
    @EnvironmentObject var spotify: SpotifyClient
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !embedded { Text(service.capitalized).font(.system(size: 15, weight: .bold)) }
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
            if !embedded { HStack { Spacer(); FlatButton(title: "Fine", prominent: true, width: 90) { dismiss() } } }
        }
        .padding(embedded ? 0 : 20).frame(maxWidth: embedded ? 520 : 460, alignment: .leading)
        .padding(.vertical, embedded ? 8 : 0)
        .background(embedded ? Color.clear : Theme.panel)
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
