import Foundation
import AppKit

/// Voicemod integration through the public Voicemod Control API (WebSocket on localhost).
/// Needs a personal API key requested from Voicemod.
@MainActor
final class VoicemodClient: ObservableObject {
    struct Voice: Identifiable, Hashable { let id: String; let name: String }
    struct Sound: Identifiable, Hashable { let id: String; let name: String }
    struct Soundboard: Identifiable, Hashable { let id: String; let name: String; let sounds: [Sound] }

    @Published private(set) var connected = false
    @Published private(set) var lastError: String?
    @Published private(set) var voices: [Voice] = []
    @Published private(set) var soundboards: [Soundboard] = []
    @Published private(set) var currentVoice = ""
    @Published private(set) var changerOn = false
    @Published private(set) var backgroundOn = false
    @Published private(set) var hearOn = false
    @Published private(set) var micMuted = false
    @Published private(set) var muteForMeOn = false
    /// Voice / sound icons provided by Voicemod, by id.
    @Published private(set) var images: [String: NSImage] = [:]

    var onChange: (() -> Void)?

    static let ports = [59129, 20000, 39273, 42152, 43782, 46667, 35679, 37170, 38501, 33952, 30546]

    private var socket: URLSessionWebSocketTask?
    private var retryTask: Task<Void, Never>?
    private var callbacks: [String: ([String: Any]) -> Void] = [:]
    private var enabled = false
    private var requestedImages: Set<String> = []

    var apiKey: String {
        get { Keychain.get("voicemod.apiKey") ?? "" }
        set { Keychain.set(newValue.trimmingCharacters(in: .whitespaces), for: "voicemod.apiKey") }
    }

    // MARK: Lifecycle

    func start() {
        enabled = true
        connect()
    }

    func stop() {
        enabled = false
        retryTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        setConnected(false)
    }

    func reconnect() {
        socket?.cancel(); socket = nil
        setConnected(false)
        connect()
    }

    private func connect(portIndex: Int = 0) {
        guard enabled, !connected else { return }
        guard !apiKey.isEmpty else { lastError = "API Key mancante"; return }
        guard portIndex < Self.ports.count else {
            lastError = "Voicemod non è aperto"
            scheduleRetry()
            return
        }
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(Self.ports[portIndex])/v1/")!)
        socket = task
        task.resume()
        send("registerClient", ["clientKey": apiKey])
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .success(let msg): self.process(msg); self.listen(task)
                case .failure: task.cancel(); self.connect(portIndex: portIndex + 1)
                }
            }
        }
    }

    private func listen(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .success(let msg): self.process(msg); self.listen(task)
                case .failure:
                    self.socket = nil
                    self.setConnected(false)
                    self.scheduleRetry()
                }
            }
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled, self.enabled, !self.connected else { return }
            self.connect()
        }
    }

    private func setConnected(_ on: Bool) {
        connected = on
        if on { lastError = nil }
        onChange?()
    }

    @discardableResult
    private func send(_ action: String, _ payload: [String: Any] = [:], _ done: (([String: Any]) -> Void)? = nil) -> String {
        let id = UUID().uuidString
        if let done { callbacks[id] = done }
        let m: [String: Any] = ["action": action, "id": id, "payload": payload]
        if let d = try? JSONSerialization.data(withJSONObject: m), let s = String(data: d, encoding: .utf8) {
            socket?.send(.string(s)) { _ in }
        }
        return id
    }

    private func process(_ msg: URLSessionWebSocketTask.Message) {
        var data: Data?
        switch msg {
        case .string(let s): data = s.data(using: .utf8)
        case .data(let d): data = d
        @unknown default: break
        }
        guard let data, let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        handle(m)
    }

    // MARK: Events

    private func handle(_ m: [String: Any]) {
        let type = (m["actionType"] as? String) ?? (m["action"] as? String) ?? (m["type"] as? String) ?? ""
        let obj = (m["actionObject"] as? [String: Any]) ?? (m["payload"] as? [String: Any]) ?? [:]
        let id = (m["actionID"] as? String) ?? (m["actionId"] as? String) ?? (m["id"] as? String) ?? ""
        if let cb = callbacks.removeValue(forKey: id) { cb(obj) }

        switch type {
        case "registerClient":
            if (obj["status"] as? [String: Any])?["code"] as? Int == 200 {
                setConnected(true)
                for a in ["getVoices", "getAllSoundboard", "getVoiceChangerStatus", "getBackgroundEffectStatus", "getHearMyselfStatus", "getMuteMicStatus", "getMuteMemeForMeStatus"] { send(a) }
            } else {
                lastError = "API Key non valida"
                socket?.cancel(); socket = nil
                setConnected(false)
            }
        case "getVoices":
            voices = (obj["voices"] as? [[String: Any]] ?? []).filter { $0["enabled"] as? Bool ?? true }
                .map { Voice(id: $0["id"] as? String ?? "", name: $0["friendlyName"] as? String ?? $0["id"] as? String ?? "") }
            if let cur = (m["currentVoice"] as? String) ?? (obj["currentVoice"] as? String) { currentVoice = cur }
            onChange?()
        case "getAllSoundboard":
            soundboards = (obj["soundboards"] as? [[String: Any]] ?? []).map { b in
                Soundboard(id: Self.v(b, "id"), name: Self.v(b, "name"),
                           sounds: (b["sounds"] as? [[String: Any]] ?? []).map { Sound(id: Self.v($0, "id"), name: Self.v($0, "name")) })
            }
        case "voiceChangedEvent", "voiceLoadedEvent", "getCurrentVoice":
            if let v = obj["voiceID"] as? String { currentVoice = v; onChange?() }
        case "toggleVoiceChanger", "voiceChangerEnabledEvent", "voiceChangerDisabledEvent":
            changerOn = Self.flag(type, obj, on: "voiceChangerEnabledEvent", toggle: "toggleVoiceChanger"); onChange?()
        case "toggleBackground", "backgroundEffectsEnabledEvent", "backgroundEffectsDisabledEvent":
            backgroundOn = Self.flag(type, obj, on: "backgroundEffectsEnabledEvent", toggle: "toggleBackground"); onChange?()
        case "toggleHearMyVoice", "hearMySelfEnabledEvent", "hearMySelfDisabledEvent":
            hearOn = Self.flag(type, obj, on: "hearMySelfEnabledEvent", toggle: "toggleHearMyVoice"); onChange?()
        case "toggleMuteMic", "toggleMute", "muteMicrophoneEnabledEvent", "muteMicrophoneDisabledEvent":
            micMuted = type == "muteMicrophoneEnabledEvent" || (type.hasPrefix("toggleMute") && obj["value"] as? Bool == true); onChange?()
        case "toggleMuteMemeForMe", "getMuteMemeForMeStatus":
            muteForMeOn = obj["value"] as? Bool ?? false; onChange?()
        default:
            break
        }
    }

    private static func flag(_ type: String, _ obj: [String: Any], on: String, toggle: String) -> Bool {
        type == on || (type == toggle && obj["value"] as? Bool == true)
    }

    /// Voicemod sends both "Id"/"id" and "Name"/"name".
    private static func v(_ d: [String: Any], _ key: String) -> String {
        (d[key] as? String) ?? (d[key.prefix(1).uppercased() + key.dropFirst()] as? String) ?? ""
    }

    // MARK: Icons

    /// Voice or sound icon from Voicemod (requested once, then cached).
    func image(voice: String? = nil, sound: String? = nil) -> NSImage? {
        let key = voice ?? sound ?? ""
        guard !key.isEmpty else { return nil }
        if let img = images[key] { return img }
        guard connected, !requestedImages.contains(key) else { return nil }
        requestedImages.insert(key)
        send("getBitmap", voice != nil ? ["voiceID": key] : ["memeId": key]) { [weak self] r in
            let res = (r["result"] as? [String: Any]) ?? r
            let b64 = (res["default"] as? String) ?? (res["image"] as? String) ?? ""
            if let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters), let img = NSImage(data: d) {
                self?.images[key] = img
                self?.onChange?()
            }
        }
        return nil
    }

    // MARK: Actions

    func loadVoice(_ id: String) {
        guard !id.isEmpty else { return }
        if !changerOn { send("toggleVoiceChanger") }
        send("loadVoice", ["voiceID": id])
    }
    func toggleChanger() { send("toggleVoiceChanger") }
    func activateChanger() { if !changerOn { send("toggleVoiceChanger") } }
    func toggleBackground() { send("toggleBackground") }
    func toggleHearMyself() { send("toggleHearMyVoice") }
    func toggleMute() { send("toggleMuteMic") }
    func toggleMuteForMe() { send("toggleMuteMemeForMe") }
    func stopAllSounds() { send("stopAllMemeSounds") }
    func playSound(_ id: String, down: Bool) { if !id.isEmpty { send("playMeme", ["FileName": id, "IsKeyDown": down]) } }
    func bleep(_ on: Bool) { send("setBeepSound", ["badLanguage": on ? 1 : 0]) }
}
