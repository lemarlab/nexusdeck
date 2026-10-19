import Foundation

/// Streamlabs Desktop remote-control API (JSON-RPC over WebSocket, token auth).
@MainActor
final class StreamlabsClient: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var sceneNames: [String] = []
    @Published private(set) var activeScene = ""
    @Published private(set) var sourceNames: [String] = []
    @Published private(set) var audioSourceNames: [String] = []
    @Published private(set) var muted: [String: Bool] = [:]
    @Published private(set) var streaming = false
    @Published private(set) var recording = false

    var onChange: (() -> Void)?
    private var task: URLSessionWebSocketTask?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Any?, Never>] = [:]
    private var scenes: [(id: String, name: String)] = []
    private var audioSources: [(id: String, name: String)] = []
    private var items: [(sceneID: String, itemID: String, sourceName: String, visible: Bool, resource: String)] = []

    func connect(port: Int, token: String) {
        task?.cancel()
        guard let url = URL(string: "ws://127.0.0.1:\(port)/api/websocket") else { return }
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        receive(t)
        Task {
            _ = await call("auth", resource: "TcpServerService", args: [token])
            connected = true
            _ = await call("subscribe", resource: "ScenesService", args: ["sceneSwitched"])
            _ = await call("subscribe", resource: "StreamingService", args: ["streamingStatusChange"])
            _ = await call("subscribe", resource: "StreamingService", args: ["recordingStatusChange"])
            await refresh()
        }
    }

    func disconnect() { task?.cancel(); task = nil; connected = false }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] r in
            Task { @MainActor in
                guard let self, t === self.task else { return }
                switch r {
                case .success(.string(let s)):
                    if let o = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] { self.handle(o) }
                    self.receive(t)
                case .failure: self.connected = false
                default: self.receive(t)
                }
            }
        }
    }

    private func handle(_ o: [String: Any]) {
        if let id = o["id"] as? Int, let c = pending.removeValue(forKey: id) {
            c.resume(returning: o["result"])
            return
        }
        if let res = o["result"] as? [String: Any], res["_type"] as? String == "EVENT" {
            Task { await refresh() }
        }
    }

    private func call(_ method: String, resource: String, args: [Any] = []) async -> Any? {
        guard let task else { return nil }
        let id = nextID; nextID += 1
        let msg: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": ["resource": resource, "args": args]]
        guard let d = try? JSONSerialization.data(withJSONObject: msg), let s = String(data: d, encoding: .utf8) else { return nil }
        return await withCheckedContinuation { c in
            pending[id] = c
            task.send(.string(s)) { err in if err != nil { Task { @MainActor in self.pending.removeValue(forKey: id)?.resume(returning: nil) } } }
        }
    }

    func refresh() async {
        if let list = await call("getScenes", resource: "ScenesService") as? [[String: Any]] {
            scenes = list.map { ($0["id"] as? String ?? "", $0["name"] as? String ?? "") }
            sceneNames = scenes.map(\.name)
            items = list.flatMap { sc in ((sc["nodes"] as? [[String: Any]]) ?? []).filter { $0["sceneItemId"] != nil }.map {
                (sc["id"] as? String ?? "", $0["sceneItemId"] as? String ?? "", $0["name"] as? String ?? "", $0["visible"] as? Bool ?? true, $0["resourceId"] as? String ?? "")
            } }
            sourceNames = Array(Set(items.map(\.sourceName))).sorted()
        }
        if let a = await call("activeSceneId", resource: "ScenesService") as? String { activeScene = scenes.first { $0.id == a }?.name ?? "" }
        if let src = await call("getSources", resource: "AudioService") as? [[String: Any]] {
            audioSources = src.map { ($0["sourceId"] as? String ?? "", $0["name"] as? String ?? "") }
            audioSourceNames = audioSources.map(\.name)
            for s in src { muted[s["name"] as? String ?? ""] = s["muted"] as? Bool ?? false }
        }
        if let m = await call("getModel", resource: "StreamingService") as? [String: Any] {
            streaming = (m["streamingStatus"] as? String ?? "offline") != "offline"
            recording = (m["recordingStatus"] as? String ?? "offline") != "offline"
        }
        onChange?()
    }

    func setScene(_ name: String) async {
        guard let s = scenes.first(where: { $0.name == name }) else { return }
        _ = await call("makeSceneActive", resource: "ScenesService", args: [s.id])
    }
    func toggleStream() async { _ = await call("toggleStreaming", resource: "StreamingService") }
    func toggleRecord() async { _ = await call("toggleRecording", resource: "StreamingService") }
    func toggleMute(_ name: String) async {
        guard let s = audioSources.first(where: { $0.name == name }) else { return }
        _ = await call("setMuted", resource: "AudioSource[\"\(s.id)\"]", args: [!(muted[name] ?? false)])
        await refresh()
    }
    func toggleSource(scene: String, source: String) async {
        guard let sc = scenes.first(where: { $0.name == scene }), let it = items.first(where: { $0.sceneID == sc.id && $0.sourceName == source }) else { return }
        _ = await call("setVisibility", resource: it.resource, args: [!it.visible])
        await refresh()
    }
}
