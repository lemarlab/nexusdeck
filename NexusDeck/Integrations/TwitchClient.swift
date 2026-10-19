import Foundation
import AppKit

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let author: String
    let text: String
    let colorHex: String
}

/// Twitch Helix + IRC (chat) client.
@MainActor
final class TwitchClient: ObservableObject {
    @Published private(set) var userName = ""
    @Published private(set) var viewers = 0
    @Published private(set) var followers = 0
    @Published private(set) var isLive = false
    @Published private(set) var chat: [ChatMessage] = []
    @Published private(set) var emoteOnly = false
    @Published private(set) var followersOnly = false
    @Published private(set) var slowMode = false
    @Published private(set) var subOnly = false
    @Published var pendingCode: (code: String, url: URL)?
    @Published var lastError: String?

    var clientID = ""
    var onChange: (() -> Void)?
    private var token: OAuthToken? = OAuth.load(account: "twitch")
    private var userID = ""
    private var irc: URLSessionWebSocketTask?
    private var poll: Timer?
    private var lastClipID: String?

    var isLoggedIn: Bool { token != nil && !userName.isEmpty }

    private static let scopes = "channel:manage:broadcast channel:edit:commercial clips:edit moderator:manage:chat_settings moderator:manage:chat_messages moderator:read:followers chat:read chat:edit user:read:email"

    func login() async {
        do {
            let t = try await OAuth.deviceFlow(deviceURL: "https://id.twitch.tv/oauth2/device", tokenURL: "https://id.twitch.tv/oauth2/token",
                                               clientID: clientID, scopes: Self.scopes) { code, url in self.pendingCode = (code, url) }
            pendingCode = nil
            token = t
            OAuth.store(t, account: "twitch")
            await start()
        } catch { pendingCode = nil; lastError = error.localizedDescription }
    }

    func logout() {
        token = nil
        OAuth.store(nil, account: "twitch")
        userName = ""; userID = ""
        irc?.cancel(); irc = nil
        poll?.invalidate()
    }

    func start() async {
        guard token != nil, !clientID.isEmpty else { return }
        guard let me = try? await get("users"), let u = (me["data"] as? [[String: Any]])?.first else { return }
        userID = u["id"] as? String ?? ""
        userName = u["login"] as? String ?? ""
        connectIRC()
        await refresh()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
    }

    // MARK: REST

    private func authorized() async throws -> String {
        guard var t = token else { throw OAuthError.denied }
        if t.isExpired {
            t = try await OAuth.refresh(tokenURL: "https://id.twitch.tv/oauth2/token", clientID: clientID, token: t)
            token = t
            OAuth.store(t, account: "twitch")
        }
        return t.accessToken
    }

    @discardableResult
    private func call(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://api.twitch.tv/helix/" + path)!)
        req.httpMethod = method
        req.setValue("Bearer \(try await authorized())", forHTTPHeaderField: "Authorization")
        req.setValue(clientID, forHTTPHeaderField: "Client-Id")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func get(_ path: String) async throws -> [String: Any] { try await call("GET", path) }

    func refresh() async {
        guard !userID.isEmpty else { return }
        if let s = try? await get("streams?user_id=\(userID)") {
            let st = (s["data"] as? [[String: Any]])?.first
            isLive = st != nil
            viewers = st?["viewer_count"] as? Int ?? 0
        }
        if let f = try? await get("channels/followers?broadcaster_id=\(userID)&first=1") { followers = f["total"] as? Int ?? 0 }
        if let c = try? await get("chat/settings?broadcaster_id=\(userID)&moderator_id=\(userID)"), let d = (c["data"] as? [[String: Any]])?.first {
            emoteOnly = d["emote_mode"] as? Bool ?? false
            followersOnly = d["follower_mode"] as? Bool ?? false
            slowMode = d["slow_mode"] as? Bool ?? false
            subOnly = d["subscriber_mode"] as? Bool ?? false
        }
        onChange?()
    }

    private func chatSettings(_ body: [String: Any]) async {
        _ = try? await call("PATCH", "chat/settings?broadcaster_id=\(userID)&moderator_id=\(userID)", body)
        await refresh()
    }

    func toggleEmoteOnly() async { await chatSettings(["emote_mode": !emoteOnly]) }
    func toggleFollowersOnly() async { await chatSettings(["follower_mode": !followersOnly]) }
    func toggleSlow(seconds: Int) async { await chatSettings(slowMode ? ["slow_mode": false] : ["slow_mode": true, "slow_mode_wait_time": seconds]) }
    func toggleSubOnly() async { await chatSettings(["subscriber_mode": !subOnly]) }
    func clearChat() async { _ = try? await call("DELETE", "moderation/chat?broadcaster_id=\(userID)&moderator_id=\(userID)"); chat.removeAll() }
    func createMarker() async { _ = try? await call("POST", "streams/markers", ["user_id": userID]) }

    func createClip() async {
        if let r = try? await call("POST", "clips?broadcaster_id=\(userID)"), let id = (r["data"] as? [[String: Any]])?.first?["id"] as? String { lastClipID = id }
    }

    func openLastClip() {
        if let id = lastClipID { NSWorkspace.shared.open(URL(string: "https://clips.twitch.tv/\(id)")!) }
    }

    func setTitle(_ title: String, game: String) async {
        var body: [String: Any] = [:]
        if !title.isEmpty { body["title"] = title }
        if !game.isEmpty, let g = try? await get("games?name=\(game.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"),
           let id = (g["data"] as? [[String: Any]])?.first?["id"] as? String { body["game_id"] = id }
        if !body.isEmpty { _ = try? await call("PATCH", "channels?broadcaster_id=\(userID)", body) }
    }

    // MARK: IRC chat

    private func connectIRC() {
        irc?.cancel()
        guard let t = token else { return }
        let ws = URLSession.shared.webSocketTask(with: URL(string: "wss://irc-ws.chat.twitch.tv:443")!)
        irc = ws
        ws.resume()
        for line in ["CAP REQ :twitch.tv/tags twitch.tv/commands", "PASS oauth:\(t.accessToken)", "NICK \(userName)", "JOIN #\(userName)"] {
            ws.send(.string(line)) { _ in }
        }
        receiveIRC(ws)
    }

    private func receiveIRC(_ ws: URLSessionWebSocketTask) {
        ws.receive { [weak self] r in
            Task { @MainActor in
                guard let self, ws === self.irc else { return }
                if case .success(.string(let s)) = r {
                    for line in s.split(separator: "\r\n") { self.handleIRC(String(line), ws) }
                    self.receiveIRC(ws)
                }
            }
        }
    }

    private func handleIRC(_ line: String, _ ws: URLSessionWebSocketTask) {
        if line.hasPrefix("PING") { ws.send(.string("PONG :tmi.twitch.tv")) { _ in }; return }
        guard line.contains(" PRIVMSG ") else { return }
        var tags: [String: String] = [:]
        var rest = Substring(line)
        if line.hasPrefix("@"), let sp = line.firstIndex(of: " ") {
            for kv in line[line.index(after: line.startIndex)..<sp].split(separator: ";") {
                let p = kv.split(separator: "=", maxSplits: 1)
                tags[String(p[0])] = p.count > 1 ? String(p[1]) : ""
            }
            rest = line[line.index(after: sp)...]
        }
        guard let r = rest.range(of: " :", range: rest.index(after: rest.startIndex)..<rest.endIndex) else { return }
        let text = String(rest[r.upperBound...])
        let author = tags["display-name"].flatMap { $0.isEmpty ? nil : $0 } ?? String(rest.dropFirst().prefix { $0 != "!" })
        chat.append(ChatMessage(author: author, text: text, colorHex: tags["color"].flatMap { $0.isEmpty ? nil : $0 } ?? "#9146FF"))
        if chat.count > 100 { chat.removeFirst(chat.count - 100) }
        onChange?()
    }

    func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }
        irc?.send(.string("PRIVMSG #\(userName) :\(text)")) { _ in }
        chat.append(ChatMessage(author: userName, text: text, colorHex: "#9146FF"))
    }
}
