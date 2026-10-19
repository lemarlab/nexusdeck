import Foundation
import AppKit

/// Spotify Web API playback control.
@MainActor
final class SpotifyClient: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode = "off" // off, track, context
    @Published private(set) var volume = 50
    @Published private(set) var track = ""
    @Published private(set) var artist = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var devices: [(id: String, name: String)] = []
    @Published var lastError: String?

    var clientID = ""
    var onChange: (() -> Void)?
    private var token: OAuthToken? = OAuth.load(account: "spotify")
    private var poll: Timer?
    private var artworkURL = ""

    var isLoggedIn: Bool { token != nil }

    func login() async {
        do {
            let t = try await OAuth.pkceLoopback(authURL: "https://accounts.spotify.com/authorize", tokenURL: "https://accounts.spotify.com/api/token", clientID: clientID,
                                                 scopes: "user-read-playback-state user-modify-playback-state user-read-currently-playing", port: 17_564)
            token = t
            OAuth.store(t, account: "spotify")
            start()
        } catch { lastError = error.localizedDescription }
    }

    func logout() { token = nil; OAuth.store(nil, account: "spotify"); poll?.invalidate() }

    func start() {
        guard token != nil else { return }
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
        Task { await refresh() }
    }

    @discardableResult
    private func call(_ method: String, _ path: String, body: [String: Any]? = nil) async -> [String: Any]? {
        guard var t = token else { return nil }
        if t.isExpired {
            guard let n = try? await OAuth.refresh(tokenURL: "https://accounts.spotify.com/api/token", clientID: clientID, token: t) else { return nil }
            t = n
            token = n
            OAuth.store(n, account: "spotify")
        }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/" + path)!)
        req.httpMethod = method
        req.setValue("Bearer \(t.accessToken)", forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = try? JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        else if method != "GET" { req.setValue("0", forHTTPHeaderField: "Content-Length") }
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func refresh() async {
        guard let s = await call("GET", "me/player"), !s.isEmpty else { return }
        isPlaying = s["is_playing"] as? Bool ?? false
        shuffle = s["shuffle_state"] as? Bool ?? false
        repeatMode = s["repeat_state"] as? String ?? "off"
        volume = (s["device"] as? [String: Any])?["volume_percent"] as? Int ?? volume
        if let item = s["item"] as? [String: Any] {
            track = item["name"] as? String ?? ""
            artist = ((item["artists"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            let url = (((item["album"] as? [String: Any])?["images"] as? [[String: Any]])?.last?["url"] as? String) ?? ""
            if url != artworkURL, let u = URL(string: url) {
                artworkURL = url
                if let (d, _) = try? await URLSession.shared.data(from: u) { artwork = NSImage(data: d) }
            }
        }
        onChange?()
    }

    func refreshDevices() async {
        guard let r = await call("GET", "me/player/devices") else { return }
        devices = ((r["devices"] as? [[String: Any]]) ?? []).map { ($0["id"] as? String ?? "", $0["name"] as? String ?? "") }
    }

    func playPause(deviceID: String = "") async {
        let q = deviceID.isEmpty ? "" : "?device_id=\(deviceID)"
        await call("PUT", (isPlaying ? "me/player/pause" : "me/player/play") + q)
        isPlaying.toggle(); onChange?()
    }
    func next() async { await call("POST", "me/player/next") }

    /// "Play URL": a Spotify link (open.spotify.com/…) or URI (spotify:…) of a track, album, playlist, artist or episode.
    func play(url: String, deviceID: String = "") async {
        guard let uri = Self.uri(from: url) else { return }
        let q = deviceID.isEmpty ? "" : "?device_id=\(deviceID)"
        let body: [String: Any] = uri.contains(":track:") || uri.contains(":episode:") ? ["uris": [uri]] : ["context_uri": uri]
        await call("PUT", "me/player/play" + q, body: body)
        try? await Task.sleep(for: .milliseconds(400))
        await refresh()
    }

    static func uri(from link: String) -> String? {
        let s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("spotify:") { return s }
        guard let u = URL(string: s), u.host?.contains("spotify.com") == true else { return nil }
        let parts = u.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        guard parts.count >= 2, ["track", "album", "playlist", "artist", "episode", "show"].contains(parts[0]) else { return nil }
        return "spotify:\(parts[0]):\(parts[1])"
    }
    func previous() async { await call("POST", "me/player/previous") }
    func changeVolume(_ delta: Int) async {
        volume = max(0, min(100, volume + delta))
        await call("PUT", "me/player/volume?volume_percent=\(volume)")
    }
    func toggleShuffle() async { shuffle.toggle(); await call("PUT", "me/player/shuffle?state=\(shuffle)"); onChange?() }
    func cycleRepeat() async {
        repeatMode = repeatMode == "off" ? "context" : (repeatMode == "context" ? "track" : "off")
        await call("PUT", "me/player/repeat?state=\(repeatMode)")
        onChange?()
    }
}
