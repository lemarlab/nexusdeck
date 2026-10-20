import SwiftUI
import ServiceManagement

// MARK: Discord

/// Discord credentials (Discord is built into NexusDeck).
struct BuiltInIntegrationsSettings: View {
    @EnvironmentObject var engine: ActionEngine
    @EnvironmentObject var discord: DiscordClient
    @State private var clientID = Keychain.get("discord.clientID") ?? ""
    @State private var secret = Keychain.get("discord.clientSecret") ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            discordSection
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
