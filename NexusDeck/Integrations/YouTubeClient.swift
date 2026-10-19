import Foundation

/// YouTube Data API v3: live viewers, subscribers and live chat.
@MainActor
final class YouTubeClient: ObservableObject {
    @Published private(set) var channelTitle = ""
    @Published private(set) var subscribers = 0
    @Published private(set) var watching = 0
    @Published private(set) var isLive = false
    @Published private(set) var chat: [ChatMessage] = []
    @Published var pendingCode: (code: String, url: URL)?
    @Published var lastError: String?

    var clientID = ""
    var clientSecret = ""
    var onChange: (() -> Void)?
    private var token: OAuthToken? = OAuth.load(account: "youtube")
    private var liveChatID: String?
    private var nextPageToken: String?
    private var poll: Timer?

    var isLoggedIn: Bool { token != nil && !channelTitle.isEmpty }

    func login() async {
        do {
            let t = try await OAuth.deviceFlow(deviceURL: "https://oauth2.googleapis.com/device/code", tokenURL: "https://oauth2.googleapis.com/token",
                                               clientID: clientID, clientSecret: clientSecret, scopes: "https://www.googleapis.com/auth/youtube.readonly") { c, u in self.pendingCode = (c, u) }
            pendingCode = nil
            token = t
            OAuth.store(t, account: "youtube")
            await start()
        } catch { pendingCode = nil; lastError = error.localizedDescription }
    }

    func logout() {
        token = nil
        OAuth.store(nil, account: "youtube")
        channelTitle = ""
        poll?.invalidate()
    }

    func start() async {
        guard token != nil, !clientID.isEmpty else { return }
        await refresh()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
    }

    private func get(_ path: String) async throws -> [String: Any] {
        guard var t = token else { throw OAuthError.denied }
        if t.isExpired {
            t = try await OAuth.refresh(tokenURL: "https://oauth2.googleapis.com/token", clientID: clientID, clientSecret: clientSecret, token: t)
            token = t
            OAuth.store(t, account: "youtube")
        }
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/youtube/v3/" + path)!)
        req.setValue("Bearer \(t.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func refresh() async {
        if let c = try? await get("channels?part=snippet,statistics&mine=true"), let ch = (c["items"] as? [[String: Any]])?.first {
            channelTitle = (ch["snippet"] as? [String: Any])?["title"] as? String ?? ""
            subscribers = Int((ch["statistics"] as? [String: Any])?["subscriberCount"] as? String ?? "") ?? 0
        }
        if let b = try? await get("liveBroadcasts?part=snippet&broadcastStatus=active&broadcastType=all"),
           let item = (b["items"] as? [[String: Any]])?.first, let id = item["id"] as? String {
            isLive = true
            liveChatID = (item["snippet"] as? [String: Any])?["liveChatId"] as? String
            if let v = try? await get("videos?part=liveStreamingDetails&id=\(id)"),
               let d = ((v["items"] as? [[String: Any]])?.first?["liveStreamingDetails"]) as? [String: Any] {
                watching = Int(d["concurrentViewers"] as? String ?? "") ?? 0
            }
            await fetchChat()
        } else {
            isLive = false
            watching = 0
        }
        onChange?()
    }

    private func fetchChat() async {
        guard let id = liveChatID else { return }
        var path = "liveChat/messages?part=snippet,authorDetails&liveChatId=\(id)"
        if let p = nextPageToken { path += "&pageToken=\(p)" }
        guard let r = try? await get(path) else { return }
        nextPageToken = r["nextPageToken"] as? String
        for m in (r["items"] as? [[String: Any]]) ?? [] {
            let author = (m["authorDetails"] as? [String: Any])?["displayName"] as? String ?? ""
            let text = (m["snippet"] as? [String: Any])?["displayMessage"] as? String ?? ""
            chat.append(ChatMessage(author: author, text: text, colorHex: "#FF4E45"))
        }
        if chat.count > 100 { chat.removeFirst(chat.count - 100) }
    }
}
