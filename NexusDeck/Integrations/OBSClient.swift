import Foundation
import CryptoKit
import AppKit

/// Client for obs-websocket protocol v5.
@MainActor
final class OBSClient: ObservableObject {
    enum Status: Equatable { case disconnected, connecting, connected, failed(String) }

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var sceneNames: [String] = []
    @Published private(set) var programScene = ""
    @Published private(set) var previewScene = ""
    @Published private(set) var studioMode = false
    @Published private(set) var recording = false
    @Published private(set) var recordPaused = false
    @Published private(set) var streaming = false
    @Published private(set) var virtualCam = false
    @Published private(set) var inputNames: [String] = []
    @Published private(set) var audioInputNames: [String] = []
    @Published private(set) var inputMuted: [String: Bool] = [:]
    @Published private(set) var profiles: [String] = []
    @Published private(set) var currentProfile = ""
    @Published private(set) var collections: [String] = []
    @Published private(set) var currentCollection = ""
    @Published private(set) var transitions: [String] = []
    @Published private(set) var hotkeys: [String] = []
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var droppedFrames = 0
    @Published private(set) var skippedFrames = 0
    @Published private(set) var sceneItemsByScene: [String: [(id: Int, name: String, enabled: Bool)]] = [:]

    /// Called after any state change so keys can refresh.
    var onChange: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var host = "127.0.0.1"
    var hostDescription: String { "\(host == "127.0.0.1" ? "questo Mac" : host):\(port)" }
    private var port = 4455
    private var password = ""
    private var reconnect = true
    private var statsTimer: Timer?

    var isConnected: Bool { status == .connected }

    func sceneItems(_ scene: String) -> [String] { sceneItemsByScene[scene]?.map(\.name) ?? [] }

    func configure(host: String, port: Int, password: String) {
        self.host = host
        self.port = port
        self.password = password
    }

    func connect() {
        disconnect(keepRetrying: true)
        guard let url = URL(string: "ws://\(host):\(port)") else { return }
        status = .connecting
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        receive(t)
    }

    func disconnect(keepRetrying: Bool = false) {
        reconnect = keepRetrying
        statsTimer?.invalidate()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        for (_, c) in pending { c.resume(throwing: CancellationError()) }
        pending.removeAll()
        if !keepRetrying { status = .disconnected }
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, t === self.task else { return }
                switch result {
                case .success(let msg):
                    if case .string(let s) = msg, let d = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        self.handle(obj)
                    }
                    self.receive(t)
                case .failure(let err):
                    self.status = .failed(err.localizedDescription)
                    self.task = nil
                    if self.reconnect {
                        try? await Task.sleep(for: .seconds(5))
                        if self.reconnect, self.task == nil { self.connect() }
                    }
                }
            }
        }
    }

    private func send(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    private func handle(_ msg: [String: Any]) {
        let op = msg["op"] as? Int ?? -1
        let d = msg["d"] as? [String: Any] ?? [:]
        switch op {
        case 0: // Hello
            var identify: [String: Any] = ["rpcVersion": 1, "eventSubscriptions": 0x7FF | (1 << 16)]
            if let auth = d["authentication"] as? [String: Any], let salt = auth["salt"] as? String, let challenge = auth["challenge"] as? String {
                let secret = Data(SHA256.hash(data: Data((password + salt).utf8))).base64EncodedString()
                identify["authentication"] = Data(SHA256.hash(data: Data((secret + challenge).utf8))).base64EncodedString()
            }
            send(["op": 1, "d": identify])
        case 2: // Identified
            status = .connected
            Task { await refreshAll() }
            statsTimer?.invalidate()
            statsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refreshStats() } }
        case 5: handleEvent(d["eventType"] as? String ?? "", d["eventData"] as? [String: Any] ?? [:])
        case 7:
            if let id = d["requestId"] as? String, let c = pending.removeValue(forKey: id) {
                let st = d["requestStatus"] as? [String: Any] ?? [:]
                if st["result"] as? Bool == true { c.resume(returning: d["responseData"] as? [String: Any] ?? [:]) }
                else { c.resume(throwing: NSError(domain: "OBS", code: st["code"] as? Int ?? 0, userInfo: [NSLocalizedDescriptionKey: st["comment"] as? String ?? "Errore OBS"])) }
            }
        default: break
        }
    }

    @discardableResult
    func request(_ type: String, _ data: [String: Any] = [:]) async throws -> [String: Any] {
        guard task != nil, status == .connected else { throw NSError(domain: "OBS", code: -1, userInfo: [NSLocalizedDescriptionKey: "OBS non connesso"]) }
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { c in
            pending[id] = c
            send(["op": 6, "d": ["requestType": type, "requestId": id, "requestData": data]])
        }
    }

    private func handleEvent(_ type: String, _ d: [String: Any]) {
        switch type {
        case "CurrentProgramSceneChanged": programScene = d["sceneName"] as? String ?? ""
        case "CurrentPreviewSceneChanged": previewScene = d["sceneName"] as? String ?? ""
        case "StudioModeStateChanged": studioMode = d["studioModeEnabled"] as? Bool ?? false
        case "RecordStateChanged":
            let s = d["outputState"] as? String ?? ""
            recording = d["outputActive"] as? Bool ?? false
            recordPaused = s == "OBS_WEBSOCKET_OUTPUT_PAUSED"
            if s == "OBS_WEBSOCKET_OUTPUT_RESUMED" { recordPaused = false }
        case "StreamStateChanged": streaming = d["outputActive"] as? Bool ?? false
        case "VirtualcamStateChanged": virtualCam = d["outputActive"] as? Bool ?? false
        case "InputMuteStateChanged":
            if let n = d["inputName"] as? String { inputMuted[n] = d["inputMuted"] as? Bool ?? false }
        case "SceneItemEnableStateChanged":
            if let scene = d["sceneName"] as? String, let id = d["sceneItemId"] as? Int, var items = sceneItemsByScene[scene], let i = items.firstIndex(where: { $0.id == id }) {
                items[i].enabled = d["sceneItemEnabled"] as? Bool ?? false
                sceneItemsByScene[scene] = items
            }
        case "SceneListChanged", "InputCreated", "InputRemoved", "InputNameChanged", "SceneCreated", "SceneRemoved", "SceneNameChanged", "SceneItemCreated", "SceneItemRemoved":
            Task { await refreshAll() }
        case "CurrentProfileChanged": currentProfile = d["profileName"] as? String ?? ""
        case "CurrentSceneCollectionChanged": Task { await refreshAll() }
        case "ExitStarted": status = .disconnected
        default: return
        }
        onChange?()
    }

    func refreshAll() async {
        do {
            let scenes = try await request("GetSceneList")
            sceneNames = ((scenes["scenes"] as? [[String: Any]]) ?? []).compactMap { $0["sceneName"] as? String }.reversed()
            programScene = scenes["currentProgramSceneName"] as? String ?? ""
            previewScene = scenes["currentPreviewSceneName"] as? String ?? ""
            let inputs = try await request("GetInputList")
            inputNames = ((inputs["inputs"] as? [[String: Any]]) ?? []).compactMap { $0["inputName"] as? String }
            var audio: [String] = []
            for n in inputNames {
                if let m = try? await request("GetInputMute", ["inputName": n]) {
                    inputMuted[n] = m["inputMuted"] as? Bool ?? false
                    audio.append(n)
                }
            }
            audioInputNames = audio
            for s in sceneNames {
                let items = try await request("GetSceneItemList", ["sceneName": s])
                sceneItemsByScene[s] = ((items["sceneItems"] as? [[String: Any]]) ?? []).map { ($0["sceneItemId"] as? Int ?? 0, $0["sourceName"] as? String ?? "", $0["sceneItemEnabled"] as? Bool ?? false) }
            }
            let rec = try await request("GetRecordStatus")
            recording = rec["outputActive"] as? Bool ?? false
            recordPaused = rec["outputPaused"] as? Bool ?? false
            streaming = (try await request("GetStreamStatus"))["outputActive"] as? Bool ?? false
            virtualCam = (try? await request("GetVirtualCamStatus"))?["outputActive"] as? Bool ?? false
            studioMode = (try await request("GetStudioModeEnabled"))["studioModeEnabled"] as? Bool ?? false
            let p = try await request("GetProfileList")
            profiles = p["profiles"] as? [String] ?? []
            currentProfile = p["currentProfileName"] as? String ?? ""
            let c = try await request("GetSceneCollectionList")
            collections = c["sceneCollections"] as? [String] ?? []
            currentCollection = c["currentSceneCollectionName"] as? String ?? ""
            transitions = ((try await request("GetSceneTransitionList"))["transitions"] as? [[String: Any]] ?? []).compactMap { $0["transitionName"] as? String }
            hotkeys = (try await request("GetHotkeyList"))["hotkeys"] as? [String] ?? []
            onChange?()
        } catch {}
    }

    private func refreshStats() async {
        guard let s = try? await request("GetStats") else { return }
        cpuUsage = s["cpuUsage"] as? Double ?? 0
        if let st = try? await request("GetStreamStatus") {
            droppedFrames = st["outputSkippedFrames"] as? Int ?? 0
        }
        skippedFrames = s["outputSkippedFrames"] as? Int ?? 0
        onChange?()
    }

    // MARK: Commands

    func setScene(_ name: String) async {
        if studioMode { _ = try? await request("SetCurrentPreviewScene", ["sceneName": name]) }
        else { _ = try? await request("SetCurrentProgramScene", ["sceneName": name]) }
    }
    func toggleRecord() async { _ = try? await request("ToggleRecord") }
    func toggleRecordPause() async { _ = try? await request("ToggleRecordPause") }
    func toggleStream() async { _ = try? await request("ToggleStream") }
    func toggleVirtualCam() async { _ = try? await request("ToggleVirtualCam") }
    func toggleMute(_ input: String) async { _ = try? await request("ToggleInputMute", ["inputName": input]) }
    func toggleStudioMode() async { _ = try? await request("SetStudioModeEnabled", ["studioModeEnabled": !studioMode]) }
    func previewToProgram() async { _ = try? await request("TriggerStudioModeTransition") }
    func setProfile(_ n: String) async { _ = try? await request("SetCurrentProfile", ["profileName": n]) }
    func setCollection(_ n: String) async { _ = try? await request("SetCurrentSceneCollection", ["sceneCollectionName": n]) }
    func setTransition(_ n: String) async { _ = try? await request("SetCurrentSceneTransition", ["transitionName": n]) }
    func triggerHotkey(_ n: String) async { _ = try? await request("TriggerHotkeyByName", ["hotkeyName": n]) }
    func setMonitorType(_ input: String, _ t: String) async { _ = try? await request("SetInputAudioMonitorType", ["inputName": input, "monitorType": t]) }

    func volumePercent(_ input: String) async -> Double {
        guard let r = try? await request("GetInputVolume", ["inputName": input]) else { return 0 }
        return (r["inputVolumeMul"] as? Double ?? 0) * 100
    }
    func setVolumePercent(_ input: String, _ v: Double) async {
        _ = try? await request("SetInputVolume", ["inputName": input, "inputVolumeMul": max(0, min(100, v)) / 100])
    }
    func changeVolume(_ input: String, by delta: Double) async {
        let v = await volumePercent(input)
        await setVolumePercent(input, v + delta)
    }

    func toggleSource(scene: String, source: String) async -> Bool? {
        guard let item = sceneItemsByScene[scene]?.first(where: { $0.name == source }) else { return nil }
        _ = try? await request("SetSceneItemEnabled", ["sceneName": scene, "sceneItemId": item.id, "sceneItemEnabled": !item.enabled])
        return !item.enabled
    }

    func setSource(scene: String, source: String, enabled: Bool) async {
        guard let item = sceneItemsByScene[scene]?.first(where: { $0.name == source }) else { return }
        _ = try? await request("SetSceneItemEnabled", ["sceneName": scene, "sceneItemId": item.id, "sceneItemEnabled": enabled])
    }

    func toggleFilter(source: String, filter: String) async -> Bool? {
        guard let f = try? await request("GetSourceFilter", ["sourceName": source, "filterName": filter]) else { return nil }
        let en = !(f["filterEnabled"] as? Bool ?? false)
        _ = try? await request("SetSourceFilterEnabled", ["sourceName": source, "filterName": filter, "filterEnabled": en])
        return en
    }

    private var sceneHistory: [String] = []
    func previousScene() async {
        guard sceneHistory.count >= 2 else { return }
        await setScene(sceneHistory[sceneHistory.count - 2])
    }
    func noteSceneChange() {
        if sceneHistory.last != programScene { sceneHistory.append(programScene) }
        if sceneHistory.count > 20 { sceneHistory.removeFirst() }
    }

    func screenshot(of source: String, width: Int = 320) async -> NSImage? {
        guard let r = try? await request("GetSourceScreenshot", ["sourceName": source, "imageFormat": "jpg", "imageWidth": width, "imageCompressionQuality": 70]),
              let s = r["imageData"] as? String, let comma = s.firstIndex(of: ","),
              let d = Data(base64Encoded: String(s[s.index(after: comma)...])) else { return nil }
        return NSImage(data: d)
    }
}
