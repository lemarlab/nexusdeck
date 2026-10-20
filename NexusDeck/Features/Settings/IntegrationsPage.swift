import SwiftUI

/// Sidebar page "Integrazioni": one card per service (status at a glance) and the settings of the selected one.
struct IntegrationsPage: View {
    @EnvironmentObject var obs: OBSClient
    @EnvironmentObject var streamlabs: StreamlabsClient
    @EnvironmentObject var discord: DiscordClient
    @EnvironmentObject var twitch: TwitchClient
    @EnvironmentObject var youtube: YouTubeClient
    @EnvironmentObject var spotify: SpotifyClient
    @State private var selected: Service = .obs

    enum Service: String, CaseIterable, Identifiable {
        case obs, streamlabs, discord, twitch, youtube, spotify
        var id: String { rawValue }
        var title: String {
            switch self {
            case .obs: "OBS Studio"
            case .streamlabs: "Streamlabs Desktop"
            case .discord: "Discord"
            case .twitch: "Twitch"
            case .youtube: "YouTube"
            case .spotify: "Spotify"
            }
        }
        var summary: String {
            switch self {
            case .obs: "Scene, registrazione, diretta, sorgenti e anteprime sul display."
            case .streamlabs: "Scene e controllo della diretta con Streamlabs."
            case .discord: "Muto, audio, premi per parlare, canali vocali e testuali."
            case .twitch: "Marker, clip, chat, titolo e pubblicità della diretta."
            case .youtube: "Stato della diretta, spettatori e messaggi."
            case .spotify: "Riproduzione, brano in corso e volume."
            }
        }
        var symbol: String {
            switch self {
            case .obs: "record.circle"
            case .streamlabs: "dot.radiowaves.left.and.right"
            case .discord: "bubble.left.and.bubble.right.fill"
            case .twitch: "bubble.left.fill"
            case .youtube: "play.rectangle.fill"
            case .spotify: "music.note"
            }
        }
        var tint: String {
            switch self {
            case .obs: "#3A3A3F"
            case .streamlabs: "#1E8C7E"
            case .discord: "#5865F2"
            case .twitch: "#9146FF"
            case .youtube: "#E62117"
            case .spotify: "#1DB954"
            }
        }
    }

    private func status(_ s: Service) -> (Bool, String) {
        switch s {
        case .obs: return (obs.isConnected, obs.isConnected ? "Connesso · \(obs.hostDescription)" : "Non collegato")
        case .streamlabs: return (streamlabs.connected, streamlabs.connected ? "Connesso" : "Non collegato")
        case .discord: return (discord.isConnected, discord.isConnected ? (discord.account.isEmpty ? "Connesso" : "Connesso come \(discord.account)") : "Non collegato")
        case .twitch: return (twitch.isLoggedIn, twitch.isLoggedIn ? "Connesso come \(twitch.userName)" : "Non collegato")
        case .youtube: return (youtube.isLoggedIn, youtube.isLoggedIn ? "Connesso · \(youtube.channelTitle)" : "Non collegato")
        case .spotify: return (spotify.isLoggedIn, spotify.isLoggedIn ? "Connesso" : "Non collegato")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                ForEach(Service.allCases) { card($0) }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    SidebarIcon(symbol: selected.symbol, tint: Color(hex: selected.tint))
                    Text(selected.title).font(.system(size: 15, weight: .bold))
                }
                .padding(.leading, 24)
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
    }

    private func card(_ s: Service) -> some View {
        let (ok, text) = status(s)
        let on = selected == s
        return Button { withAnimation(.easeOut(duration: 0.15)) { selected = s } } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Color(hex: Theme.lighten(s.tint, 0.18)), Color(hex: s.tint)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 48, height: 48)
                        .overlay(Image(systemName: s.symbol).font(.system(size: 21, weight: .medium)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title).font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 5) {
                            Circle().fill(ok ? Color.green : Theme.textFaint).frame(width: 7, height: 7)
                            Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.textDim).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text(s.summary).font(.system(size: 12)).foregroundStyle(Theme.textDim).lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
                Text(ok ? "Impostazioni" : "Collega").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ok ? Theme.accent : .white)
                    .padding(.horizontal, 14).frame(height: 26)
                    .background(ok ? Theme.accent.opacity(0.14) : Theme.accent)
                    .clipShape(Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? Theme.accent : Theme.cardBorder, lineWidth: on ? 2 : 1))
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var detail: some View {
        switch selected {
        case .obs: OBSPage()
        case .streamlabs: StreamlabsPage()
        case .discord: BuiltInIntegrationsSettings().padding(.horizontal, 24).padding(.vertical, 8)
        case .twitch: AccountSheet(service: "twitch", embedded: true).padding(.horizontal, 24)
        case .youtube: AccountSheet(service: "youtube", embedded: true).padding(.horizontal, 24)
        case .spotify: AccountSheet(service: "spotify", embedded: true).padding(.horizontal, 24)
        }
    }
}
