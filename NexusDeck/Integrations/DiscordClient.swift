import Foundation

/// Discord local RPC client (Unix socket "discord-ipc-N"), as documented by Discord.
/// Frames: little-endian opcode + length, then JSON. Runs its reads on a background queue.
final class DiscordIPC: @unchecked Sendable {
    enum Op: UInt32 { case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4 }

    private var fd: Int32 = -1
    private let queue = DispatchQueue(label: "nexusdeck.discord.ipc")
    private let lock = NSLock()
    /// Called on the main queue for each frame received, and with nil when the socket closes.
    var onMessage: (([String: Any]?) -> Void)?

    var isOpen: Bool { lock.withLock { fd >= 0 } }

    func connect(clientID: String) -> Bool {
        close()
        let dirs = [NSTemporaryDirectory(), ProcessInfo.processInfo.environment["TMPDIR"] ?? "", "/tmp/"].filter { !$0.isEmpty }
        for dir in dirs {
            for i in 0..<10 {
                let path = (dir as NSString).appendingPathComponent("discord-ipc-\(i)")
                guard FileManager.default.fileExists(atPath: path) else { continue }
                let s = socket(AF_UNIX, SOCK_STREAM, 0)
                guard s >= 0 else { continue }
                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                let bytes = Array(path.utf8CString)
                guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { Darwin.close(s); continue }
                withUnsafeMutableBytes(of: &addr.sun_path) { raw in bytes.withUnsafeBytes { raw.copyMemory(from: $0) } }
                let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
                if ok == 0 {
                    var one: Int32 = 1
                    setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                    lock.withLock { fd = s }
                    startReading(s)
                    send(.handshake, ["v": 1, "client_id": clientID])
                    return true
                }
                Darwin.close(s)
            }
        }
        return false
    }

    func close() {
        let s: Int32 = lock.withLock { let s = fd; fd = -1; return s }
        if s >= 0 { Darwin.shutdown(s, SHUT_RDWR); Darwin.close(s) }
    }

    @discardableResult
    func send(_ op: Op, _ obj: [String: Any]) -> Bool {
        guard let body = try? JSONSerialization.data(withJSONObject: obj) else { return false }
        var header = Data()
        var o = op.rawValue.littleEndian, l = UInt32(body.count).littleEndian
        header.append(Data(bytes: &o, count: 4)); header.append(Data(bytes: &l, count: 4))
        let packet = header + body
        let s = lock.withLock { fd }
        guard s >= 0 else { return false }
        return packet.withUnsafeBytes { Darwin.write(s, $0.baseAddress, packet.count) } == packet.count
    }

    private func readExactly(_ s: Int32, _ n: Int) -> Data? {
        var out = Data(capacity: n)
        var buf = [UInt8](repeating: 0, count: min(max(n, 1), 65536))
        while out.count < n {
            let r = Darwin.read(s, &buf, min(buf.count, n - out.count))
            if r <= 0 { return nil }
            out.append(buf, count: r)
        }
        return out
    }

    private func startReading(_ s: Int32) {
        queue.async { [weak self] in
            while let self {
                guard let head = self.readExactly(s, 8) else { break }
                let op = head[0..<4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
                let len = Int(head[4..<8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
                guard len < 16_000_000, let body = self.readExactly(s, len) else { break }
                if op == Op.ping.rawValue { self.send(.pong, (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]); continue }
                if op == Op.close.rawValue { break }
                let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                DispatchQueue.main.async { self.onMessage?(obj) }
            }
            DispatchQueue.main.async { self?.onMessage?(nil) }
        }
    }
}

/// Discord integration (local RPC): mute, deafen, push-to-talk/mute and channels.
/// Needs a Client ID / Secret created by the user in the Discord developer portal.
@MainActor
final class DiscordClient: ObservableObject {
    enum Status: Equatable { case off, connecting, connected, failed(String) }
    struct Guild: Identifiable, Hashable { let id: String; let name: String }
    struct Channel: Identifiable, Hashable { let id: String; let name: String; let voice: Bool }

    @Published private(set) var status: Status = .off
    @Published private(set) var account = ""
    @Published private(set) var muted = false
    @Published private(set) var deafened = false
    @Published private(set) var voiceChannel: String?
    @Published private(set) var guilds: [Guild] = []
    @Published private(set) var channels: [String: [Channel]] = [:]

    var onChange: (() -> Void)?

    private let ipc = DiscordIPC()
    private var pending: [String: ([String: Any]) -> Void] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var enabled = false

    var clientID: String { Keychain.get("discord.clientID") ?? "" }
    var clientSecret: String { Keychain.get("discord.clientSecret") ?? "" }
    var isConnected: Bool { status == .connected }

    init() { ipc.onMessage = { [weak self] m in self?.handle(m) } }

    // MARK: Lifecycle

    func start() {
        enabled = true
        connect()
    }

    func stop() {
        enabled = false
        reconnectTask?.cancel()
        ipc.close()
        set(.off)
    }

    func configure(clientID: String, secret: String) {
        let id = clientID.trimmingCharacters(in: .whitespaces)
        if id != self.clientID { Keychain.set(nil, for: "discord.accessToken"); Keychain.set(nil, for: "discord.refreshToken") }
        Keychain.set(id, for: "discord.clientID")
        Keychain.set(secret.trimmingCharacters(in: .whitespaces), for: "discord.clientSecret")
        ipc.close()
        connect()
    }

    func signOut() {
        Keychain.set(nil, for: "discord.accessToken")
        Keychain.set(nil, for: "discord.refreshToken")
        reconnectTask?.cancel()
        ipc.close()
        account = ""
        set(.off)
    }

    private func set(_ s: Status) {
        status = s
        onChange?()
    }

    private func connect() {
        guard enabled, !clientID.isEmpty else { set(.off); return }
        set(.connecting)
        if ipc.connect(clientID: clientID) { return }
        set(.failed("Discord non è aperto"))
        scheduleReconnect()
    }

    /// Discord may start after NexusDeck: retry quietly.
    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled, self.enabled, !self.ipc.isOpen else { return }
            self.connect()
        }
    }

    // MARK: RPC

    private func command(_ cmd: String, _ args: [String: Any] = [:], evt: String? = nil, _ done: (([String: Any]) -> Void)? = nil) {
        let nonce = UUID().uuidString
        if let done { pending[nonce] = done }
        var m: [String: Any] = ["cmd": cmd, "args": args, "nonce": nonce]
        if let evt { m["evt"] = evt }
        ipc.send(.frame, m)
    }

    private func handle(_ m: [String: Any]?) {
        guard let m else {
            pending.removeAll()
            if enabled { set(.failed("Discord non è aperto")); scheduleReconnect() }
            return
        }
        let data = m["data"] as? [String: Any] ?? [:]
        if let nonce = m["nonce"] as? String, let done = pending.removeValue(forKey: nonce) { done(m); return }
        guard m["cmd"] as? String == "DISPATCH" else { return }
        switch m["evt"] as? String {
        case "READY": authenticate()
        case "VOICE_SETTINGS_UPDATE": applyVoice(data)
        case "VOICE_CHANNEL_SELECT":
            voiceChannel = data["channel_id"] as? String
            onChange?()
        default: break
        }
    }

    private func authenticate() {
        if let token = Keychain.get("discord.accessToken") {
            command("AUTHENTICATE", ["access_token": token]) { [weak self] r in
                guard let self else { return }
                if r["evt"] as? String == "ERROR" { self.refreshToken() } else { self.authenticated(r) }
            }
        } else {
            authorize()
        }
    }

    private func authorize() {
        command("AUTHORIZE", ["client_id": clientID, "scopes": ["rpc", "rpc.voice.read", "rpc.voice.write"]]) { [weak self] r in
            guard let self else { return }
            guard let code = (r["data"] as? [String: Any])?["code"] as? String else { self.set(.failed("Autorizzazione negata in Discord")); return }
            self.exchange(["grant_type": "authorization_code", "code": code])
        }
    }

    private func refreshToken() {
        guard let refresh = Keychain.get("discord.refreshToken") else { authorize(); return }
        exchange(["grant_type": "refresh_token", "refresh_token": refresh])
    }

    private func exchange(_ fields: [String: String]) {
        var all = fields
        all["client_id"] = clientID
        all["client_secret"] = clientSecret
        var req = URLRequest(url: URL(string: "https://discord.com/api/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = all.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        Task { [weak self] in
            let result = try? await URLSession.shared.data(for: req)
            guard let self else { return }
            guard let data = result?.0, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = j["access_token"] as? String else {
                if fields["grant_type"] == "refresh_token" { self.authorize() } else { self.set(.failed("Client ID o Secret non validi")) }
                return
            }
            Keychain.set(token, for: "discord.accessToken")
            if let r = j["refresh_token"] as? String { Keychain.set(r, for: "discord.refreshToken") }
            self.command("AUTHENTICATE", ["access_token": token]) { [weak self] r in
                guard let self else { return }
                if r["evt"] as? String == "ERROR" { self.set(.failed("Accesso non riuscito")) } else { self.authenticated(r) }
            }
        }
    }

    private func authenticated(_ r: [String: Any]) {
        let user = ((r["data"] as? [String: Any])?["user"] as? [String: Any]) ?? [:]
        account = user["global_name"] as? String ?? user["username"] as? String ?? ""
        set(.connected)
        command("SUBSCRIBE", evt: "VOICE_SETTINGS_UPDATE")
        command("SUBSCRIBE", evt: "VOICE_CHANNEL_SELECT")
        command("GET_VOICE_SETTINGS") { [weak self] r in self?.applyVoice(r["data"] as? [String: Any] ?? [:]) }
        command("GET_SELECTED_VOICE_CHANNEL") { [weak self] r in
            self?.voiceChannel = (r["data"] as? [String: Any])?["id"] as? String
            self?.onChange?()
        }
        loadGuilds()
    }

    private func applyVoice(_ d: [String: Any]) {
        if let m = d["mute"] as? Bool { muted = m }
        if let dd = d["deaf"] as? Bool { deafened = dd }
        onChange?()
    }

    // MARK: Servers and channels

    func loadGuilds() {
        guard isConnected else { return }
        command("GET_GUILDS") { [weak self] r in
            let list = ((r["data"] as? [String: Any])?["guilds"] as? [[String: Any]]) ?? []
            self?.guilds = list.map { Guild(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "") }
        }
    }

    func loadChannels(_ guild: String) {
        guard isConnected, !guild.isEmpty else { return }
        command("GET_CHANNELS", ["guild_id": guild]) { [weak self] r in
            let list = ((r["data"] as? [String: Any])?["channels"] as? [[String: Any]]) ?? []
            // Discord channel types: 0 = text, 2 = voice.
            self?.channels[guild] = list.compactMap { c in
                let t = c["type"] as? Int ?? -1
                guard t == 0 || t == 2 else { return nil }
                return Channel(id: c["id"] as? String ?? "", name: c["name"] as? String ?? "", voice: t == 2)
            }
        }
    }

    // MARK: Actions

    func toggleMute() { command("SET_VOICE_SETTINGS", ["mute": !muted]) }
    func toggleDeafen() { command("SET_VOICE_SETTINGS", ["deaf": !deafened]) }
    func setMuted(_ on: Bool) { command("SET_VOICE_SETTINGS", ["mute": on]) }

    func toggleVoice(_ channel: String) {
        guard !channel.isEmpty else { return }
        if channel == voiceChannel { command("SELECT_VOICE_CHANNEL", ["channel_id": NSNull()]) }
        else { command("SELECT_VOICE_CHANNEL", ["channel_id": channel, "force": true]) }
    }

    func openText(_ channel: String) {
        if !channel.isEmpty { command("SELECT_TEXT_CHANNEL", ["channel_id": channel]) }
    }
}
