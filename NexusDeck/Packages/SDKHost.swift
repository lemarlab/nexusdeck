import Foundation
import Network
import WebKit
import AppKit

/// One side of the SDK conversation: a WebSocket client (external package or property view)
/// or a package runtime built into NexusDeck.
final class SDKPeer {
    let connection: NWConnection?
    let deliver: (([String: Any]) -> Void)?
    init(connection: NWConnection) { self.connection = connection; deliver = nil }
    init(deliver: @escaping ([String: Any]) -> Void) { connection = nil; self.deliver = deliver }
    var isNative: Bool { deliver != nil }
}

/// Creator Central SDK v2 host: WebSocket server, package runtimes and event routing.
@MainActor
final class SDKHost: NSObject, ObservableObject {
    static let shared = SDKHost()

    /// Live display overrides set by packages (not persisted, as in the reference).
    @Published private(set) var titles: [UUID: [Int: String]] = [:]
    @Published private(set) var icons: [UUID: [Int: NSImage]] = [:]
    @Published private(set) var overlays: [UUID: NSImage] = [:]
    @Published private(set) var effects: [UUID: String] = [:]
    @Published private(set) var running: Set<String> = []
    @Published private(set) var log: [String] = []

    weak var store: ProfileStore?
    weak var deck: DeckController?

    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    /// Registered package connections by package UUID.
    private var packageConnections: [String: SDKPeer] = [:]
    /// Registered property view connections by property view UUID (== widget context).
    private var propertyConnections: [String: SDKPeer] = [:]

    private var processes: [String: Process] = [:]
    private var webRuntimes: [String: WKWebView] = [:]
    private var appeared: Set<UUID> = []

    static let registerPackage = "RegisterPackageV2"
    static let registerPropertyView = "RegisterPropertyView"

    // MARK: Startup

    func start(store: ProfileStore, deck: DeckController) {
        self.store = store
        self.deck = deck
        guard listener == nil else { return }
        Self.killOrphans()
        do {
            let params = NWParameters.tcp
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
            params.requiredInterfaceType = .loopback
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: .any)
            l.newConnectionHandler = { [weak self] c in
                Task { @MainActor in self?.accept(c) }
            }
            l.stateUpdateHandler = { [weak self] s in
                Task { @MainActor in
                    guard let self else { return }
                    if case .ready = s, let p = l.port?.rawValue {
                        self.port = p
                        PackageManager.shared.migrate(store)
                        self.launchAll()
                    }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            note("Server SDK non avviato: \(error.localizedDescription)")
        }
    }

    func debugLog(_ s: String) { note(s) }

    private static let logURL = ProfileStore.folder.appendingPathComponent("sdk.log")

    private func note(_ s: String) {
        let line = "\(Date()) \(s)\n"
        if let h = try? FileHandle(forWritingTo: Self.logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: Self.logURL, atomically: true, encoding: .utf8) }
        log.append(s)
        if log.count > 200 { log.removeFirst() }
    }

    private var infoJSON: [String: Any] {
        ["application": ["language": "en", "platform": "mac",
                         "platformVersion": "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).0",
                         "version": "1.1.2.73"]]
    }

    private func jsonString(_ o: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // MARK: Runtimes

    func packagesChanged() {
        if let store { PackageManager.shared.migrate(store) }
        guard port != 0 else { return }
        launchAll()
    }

    private func launchAll() {
        for p in PackageManager.shared.packages where !running.contains(p.uuid) { launch(p) }
    }

    private func launch(_ p: InstalledPackage) {
        guard port != 0 else { return }
        let target = p.file(p.runtimeTarget)
        if p.runtimeType == "bin" && !p.runsNatively {
            note("\(p.name): solo Intel, non avviato (Rosetta non è più supportata da macOS 28)")
            return
        }
        if p.runtimeType == "bin" {
            var exe = target
            if target.pathExtension == "app", let b = Bundle(url: target), let e = b.executableURL { exe = e }
            guard FileManager.default.isExecutableFile(atPath: exe.path) else { note("\(p.name): eseguibile non trovato"); return }
            let proc = Process()
            proc.executableURL = exe
            proc.currentDirectoryURL = p.directory
            proc.arguments = ["-port", "\(port)", "-packageUUID", p.uuid, "-registerEvent", Self.registerPackage, "-info", jsonString(infoJSON)]
            proc.terminationHandler = { [weak self] _ in
                Task { @MainActor in self?.running.remove(p.uuid); self?.packageConnections[p.uuid] = nil }
            }
            do { try proc.run(); processes[p.uuid] = proc; running.insert(p.uuid) } catch { note("\(p.name): \(error.localizedDescription)") }
        } else {
            let cfg = WKWebViewConfiguration()
            cfg.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
            let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 150, height: 108), configuration: cfg)
            web.navigationDelegate = self
            webRuntimes[p.uuid] = web
            web.loadFileURL(target, allowingReadAccessTo: p.directory)
            running.insert(p.uuid)
        }
    }

    func stop(package uuid: String) {
        send(toPackage: uuid, ["event": "applicationWillTerminate"])
        processes[uuid]?.terminate(); processes[uuid] = nil
        webRuntimes[uuid] = nil
        packageConnections[uuid]?.connection?.cancel(); packageConnections[uuid] = nil
        running.remove(uuid)
    }

    /// Package processes left over by a previous run that was not shut down cleanly.
    static func killOrphans() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", PackageManager.folder.path]
        try? p.run(); p.waitUntilExit()
    }

    func restart(package uuid: String) {
        stop(package: uuid)
        if let p = PackageManager.shared.package(uuid) { launch(p) }
        for k in allKeys() where PackageManager.split(k.actionID)?.0 == uuid { appeared.remove(k.id) }
        syncInstances()
    }

    func shutdown() {
        for uuid in running { stop(package: uuid) }
    }

    // MARK: Connections

    private func accept(_ c: NWConnection) {
        c.start(queue: .main)
        receive(SDKPeer(connection: c))
    }

    private func receive(_ p: SDKPeer) {
        p.connection?.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { self.handle(obj, from: p) }
                if error == nil { self.receive(p) } else { self.drop(p) }
            }
        }
    }

    private func drop(_ p: SDKPeer) {
        packageConnections = packageConnections.filter { $0.value !== p }
        propertyConnections = propertyConnections.filter { $0.value !== p }
        p.connection?.cancel()
    }

    private func write(_ p: SDKPeer, _ obj: [String: Any]) {
        if let deliver = p.deliver { deliver(obj); return }
        guard let c = p.connection, let d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        c.send(content: d, contentContext: NWConnection.ContentContext(identifier: "text", metadata: [meta]), isComplete: true, completion: .contentProcessed { _ in })
    }

    private func send(toPackage uuid: String, _ obj: [String: Any]) {
        if let c = packageConnections[uuid] { write(c, obj) }
    }

    private func send(toProperty context: String, _ obj: [String: Any]) {
        if let c = propertyConnections[context] { write(c, obj) }
    }

    // MARK: Key helpers

    private func allKeys() -> [KeyAssignment] {
        guard let store else { return [] }
        let top = store.hotkey.keys
        return top + top.flatMap(\.children)
    }

    private func key(_ context: String) -> KeyAssignment? {
        guard let id = UUID(uuidString: context) else { return nil }
        return allKeys().first { $0.id == id }
    }

    private func updateKey(_ id: UUID, _ change: (inout KeyAssignment) -> Void) {
        guard let store else { return }
        if let i = store.hotkey.keys.firstIndex(where: { $0.id == id }) {
            change(&store.hotkey.keys[i]); return
        }
        for i in store.hotkey.keys.indices {
            if let j = store.hotkey.keys[i].children.firstIndex(where: { $0.id == id }) { change(&store.hotkey.keys[i].children[j]); return }
        }
    }

    static func settings(of key: KeyAssignment) -> [String: Any] {
        guard let v = key.settings["sdk"], let d = try? JSONEncoder().encode(v) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }

    private func setSettings(_ id: UUID, _ s: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: s), let v = try? JSONDecoder().decode(JSONValue.self, from: d) else { return }
        updateKey(id) { $0.settings["sdk"] = v }
    }

    private func base(_ key: KeyAssignment, _ event: String) -> [String: Any] {
        ["widget": PackageManager.split(key.actionID)?.1 ?? "", "event": event, "context": key.id.uuidString]
    }

    // MARK: Inbound events

    private func handle(_ m: [String: Any], from c: SDKPeer) {
        let event = m["event"] as? String ?? ""
        let context = m["context"] as? String ?? ""
        let payload = m["payload"] as? [String: Any] ?? [:]
        note("<- \(event) \(context)")

        switch event {
        case Self.registerPackage:
            guard let uuid = m["uuid"] as? String else { return }
            packageConnections[uuid] = c
            note("Pacchetto registrato: \(uuid)")
            for k in allKeys() where PackageManager.split(k.actionID)?.0 == uuid { appeared.remove(k.id) }
            syncInstances()
        case Self.registerPropertyView:
            guard let uuid = m["uuid"] as? String else { return }
            propertyConnections[uuid] = c
            if let k = key(uuid) {
                var e = base(k, "didReceiveWidgetSettings"); e["payload"] = Self.settings(of: k)
                write(c, e)
                // Built-in runtimes fill the page as soon as it can receive messages.
                if let pkg = PackageManager.split(k.actionID)?.0, packageConnections[pkg]?.isNative == true {
                    send(toPackage: pkg, base(k, "propertyViewDidAppear"))
                }
            }
        case "setWidgetSettings":
            guard let k = key(context) else { return }
            setSettings(k.id, payload)
            var e = base(k, "didReceiveWidgetSettings"); e["payload"] = payload
            // The other side is notified (package <-> property view).
            if propertyConnections[context] === c { if let pkg = PackageManager.split(k.actionID)?.0 { send(toPackage: pkg, e) } }
            else { send(toProperty: context, e) }
        case "getWidgetSettings":
            guard let k = key(context) else { return }
            var e = base(k, "didReceiveWidgetSettings"); e["payload"] = Self.settings(of: k)
            write(c, e)
        case "setPackageSettings":
            let pkg = packageID(for: c, context: context)
            let s = (payload["settings"] as? [String: Any]) ?? payload
            PackageManager.shared.setPackageSettings(pkg, s)
            let e: [String: Any] = ["event": "didReceivePackageSettings", "payload": s]
            if packageConnections[pkg] === c { for (ctx, pc) in propertyConnections where key(ctx).flatMap({ PackageManager.split($0.actionID)?.0 }) == pkg { write(pc, e); _ = ctx } }
            else { send(toPackage: pkg, e) }
        case "getPackageSettings":
            let pkg = packageID(for: c, context: context)
            write(c, ["event": "didReceivePackageSettings", "payload": PackageManager.shared.packageSettings(pkg)])
        case "openUrl":
            if let s = payload["url"] as? String, let u = URL(string: s) { NSWorkspace.shared.open(u) }
        case "sendLog":
            note(payload["message"] as? String ?? "")
        case "changeTitle":
            guard let id = UUID(uuidString: context) else { return }
            titles[id, default: [:]][payload["state"] as? Int ?? 0] = payload["title"] as? String ?? ""
            redraw()
        case "changeIcon":
            guard let id = UUID(uuidString: context), let img = Self.image(payload["image"]) else { return }
            icons[id, default: [:]][payload["state"] as? Int ?? 0] = img
            redraw()
        case "changeImage":
            guard let id = UUID(uuidString: context) else { return }
            overlays[id] = Self.image(payload["image"])
            redraw()
        case "changeState":
            guard let id = UUID(uuidString: context) else { return }
            deck?.setState(id, payload["state"] as? Int ?? 0)
        case "changeFontAttribute":
            guard let id = UUID(uuidString: context) else { return }
            updateKey(id) { k in
                k.style.fontFamily = payload["family"] as? String ?? k.style.fontFamily
                if let s = payload["size"] as? Double { k.style.size = s } else if let s = payload["size"] as? Int { k.style.size = Double(s) }
                k.style.colorHex = payload["color"] as? String ?? k.style.colorHex
                k.style.bold = payload["bold"] as? Bool ?? k.style.bold
                k.style.italic = payload["italic"] as? Bool ?? k.style.italic
                k.style.underline = payload["underLine"] as? Bool ?? k.style.underline
                switch payload["hAlignment"] as? String { case "left": k.style.textAlignment = .leading; case "right": k.style.textAlignment = .trailing; default: k.style.textAlignment = .center }
            }
            redraw()
        case "changeActionEffect":
            guard let id = UUID(uuidString: context) else { return }
            let t = payload["type"] as? String ?? "clear"
            effects[id] = t == "clear" ? nil : t
            if let img = Self.image(payload["image"]) { overlays[id] = img }
            redraw()
        case "getWidgetTitle":
            guard let k = key(context) else { return }
            var e = base(k, "didReceiveWidgetTitle"); e["payload"] = k.states.map(\.title)
            write(c, e)
        case "getWidgetIcon":
            guard let k = key(context) else { return }
            var e = base(k, "didReceiveWidgetIcon"); e["payload"] = k.states.map(\.image)
            write(c, e)
        case "getFontAttribute":
            guard let k = key(context) else { return }
            var e = base(k, "didReceiveFontAttribute")
            e["payload"] = ["family": k.style.fontFamily, "size": k.style.size, "color": k.style.colorHex, "bold": k.style.bold,
                            "italic": k.style.italic, "underLine": k.style.underline,
                            "hAlignment": k.style.textAlignment == .leading ? "left" : (k.style.textAlignment == .trailing ? "right" : "center")]
            write(c, e)
        case "sendToPropertyView":
            var e = m; e["event"] = "sendToPropertyView"
            send(toProperty: context, e)
        case "sendToPackage":
            guard let k = key(context), let pkg = PackageManager.split(k.actionID)?.0 else { return }
            var e = base(k, "sendToPackage"); e["payload"] = payload
            send(toPackage: pkg, e)
        default:
            break
        }
    }

    private func packageID(for c: SDKPeer, context: String) -> String {
        if let p = packageConnections.first(where: { $0.value === c })?.key { return p }
        if let k = key(context), let p = PackageManager.split(k.actionID)?.0 { return p }
        return context
    }

    private func redraw() { deck?.needsRedraw.send() }

    static func image(_ any: Any?) -> NSImage? {
        guard var s = any as? String, !s.isEmpty else { return nil }
        if let comma = s.firstIndex(of: ","), s.hasPrefix("data:") { s = String(s[s.index(after: comma)...]) }
        return Data(base64Encoded: s, options: .ignoreUnknownCharacters).flatMap(NSImage.init(data:))
    }

    // MARK: Outbound events

    /// Sends widgetWillAppear / widgetWillDisappear so packages track the widgets present in the active profile.
    func syncInstances() {
        let present = allKeys().filter { $0.actionID.hasPrefix("pkg:") }
        let ids = Set(present.map(\.id))
        for k in present where !appeared.contains(k.id) {
            guard let pkg = PackageManager.split(k.actionID)?.0, packageConnections[pkg] != nil else { continue }
            var e = base(k, "widgetWillAppear")
            e["payload"] = ["state": deck?.stateIndex[k.id] ?? 0, "layout": 0, "settings": Self.settings(of: k)]
            send(toPackage: pkg, e)
            appeared.insert(k.id)
        }
        for id in appeared.subtracting(ids) {
            appeared.remove(id)
            // The key is gone: we no longer know its package, broadcast to all.
            for (pkg, _) in packageConnections {
                send(toPackage: pkg, ["event": "widgetWillDisappear", "context": id.uuidString, "widget": "", "payload": ["state": 0]])
            }
        }
    }

    /// Physical press / release, sent separately so hold-to-use widgets (push-to-talk) work.
    func keyDown(_ key: KeyAssignment) { sendAction(key, ["actionDown"]) }
    func keyUp(_ key: KeyAssignment) { sendAction(key, ["actionUp", "actionTriggered"]) }

    private func sendAction(_ key: KeyAssignment, _ events: [String]) {
        guard let pkg = PackageManager.split(key.actionID)?.0 else { return }
        if packageConnections[pkg] == nil, let p = PackageManager.shared.package(pkg), !running.contains(pkg) { launch(p) }
        let payload: [String: Any] = ["state": deck?.stateIndex[key.id] ?? 0]
        for ev in events {
            var e = base(key, ev); e["payload"] = payload
            send(toPackage: pkg, e)
        }
    }

    func press(_ key: KeyAssignment) {
        guard let pkg = PackageManager.split(key.actionID)?.0 else { return }
        if packageConnections[pkg] == nil, let p = PackageManager.shared.package(pkg), !running.contains(pkg) { launch(p) }
        let payload: [String: Any] = ["state": deck?.stateIndex[key.id] ?? 0]
        for ev in ["actionDown", "actionUp", "actionTriggered"] {
            var e = base(key, ev); e["payload"] = payload
            send(toPackage: pkg, e)
        }
    }

    func propertyViewAppeared(_ key: KeyAssignment) {
        guard let pkg = PackageManager.split(key.actionID)?.0, packageConnections[pkg]?.isNative != true else { return }
        send(toPackage: pkg, base(key, "propertyViewDidAppear"))
    }

    func propertyViewDisappeared(_ key: KeyAssignment) {
        guard let pkg = PackageManager.split(key.actionID)?.0 else { return }
        send(toPackage: pkg, base(key, "propertyViewDidDisappear"))
        propertyConnections[key.id.uuidString]?.connection?.cancel()
        propertyConnections[key.id.uuidString] = nil
    }

    /// Script called by the property view page once loaded.
    func propertyViewConnectScript(_ key: KeyAssignment) -> String {
        let widgetInfo: [String: Any] = ["widget": PackageManager.split(key.actionID)?.1 ?? "", "context": key.id.uuidString,
                                         "payload": ["settings": Self.settings(of: key)]]
        return "connectCreatorCentral(\(port), '\(key.id.uuidString)', '\(Self.registerPropertyView)', \(jsonString(infoJSON)), \(jsonString(widgetInfo)))"
    }
}

extension SDKHost: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let uuid = self.webRuntimes.first(where: { $0.value === webView })?.key else { return }
            let script = "connectCreatorCentral(\(self.port), '\(uuid)', '\(Self.registerPackage)', \(self.jsonString(self.infoJSON)))"
            _ = try? await webView.evaluateJavaScript(script)
        }
    }
}
