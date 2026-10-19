import Foundation
import AppKit

/// One widget declared in a package's PackageConfig.json.
struct PackageWidget: Identifiable, Hashable {
    let uuid: String
    let name: String
    let icon: String
    let tooltip: String
    let propertyViewPath: String?
    let multiActionSupported: Bool
    let titleEditable: Bool
    let iconEditable: Bool
    let states: [(image: String, title: String)]
    let layouts: [(title: String, width: Int, height: Int)]

    var id: String { uuid }
    static func == (a: PackageWidget, b: PackageWidget) -> Bool { a.uuid == b.uuid }
    func hash(into h: inout Hasher) { h.combine(uuid) }
}

/// An installed Creator Central SDK v2 package.
struct InstalledPackage: Identifiable {
    let uuid: String
    let name: String
    let author: String
    let description: String
    let version: String
    let icon: String
    let directory: URL
    let runtimeType: String   // "bin" or "web"
    let runtimeTarget: String
    let widgets: [PackageWidget]

    var id: String { uuid }
    func file(_ relative: String) -> URL { directory.appendingPathComponent(relative) }

    /// Executable of a "bin" package (inside the .app bundle when the target is an app).
    var executable: URL? {
        guard runtimeType == "bin" else { return nil }
        let target = file(runtimeTarget)
        if target.pathExtension == "app" { return Bundle(url: target)?.executableURL }
        return target
    }

    /// False for Intel-only binaries: they need Rosetta, which macOS 28 no longer runs.
    var runsNatively: Bool {
        guard let exe = executable else { return true }
        return MachO.hasArm64(exe)
    }
}

enum MachO {
    /// Reads the Mach-O header (thin or universal) and reports whether it contains arm64 code.
    static func hasArm64(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard let head = try? h.read(upToCount: 4096), head.count >= 8 else { return false }
        func be32(_ o: Int) -> UInt32 { head[o..<o + 4].reduce(0) { $0 << 8 | UInt32($1) } }
        func le32(_ o: Int) -> UInt32 { head[o..<o + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) } }
        let arm64: UInt32 = 0x0100000C
        switch be32(0) {
        case 0xCAFEBABE, 0xCAFEBABF:
            let n = Int(be32(4)), stride = be32(0) == 0xCAFEBABF ? 32 : 20
            for i in 0..<n where 8 + i * stride + 4 <= head.count {
                if be32(8 + i * stride) == arm64 { return true }
            }
            return false
        case 0xCFFAEDFE:
            return le32(4) == arm64
        default:
            return false
        }
    }
}

/// Public catalogue entry of the official store (package files are publicly downloadable).
struct CatalogPackage: Identifiable, Hashable {
    let id: String          // package UUID as declared inside the package
    let name: String
    let author: String
    let summary: String
    let url: URL
    let iconURL: URL?
}

/// Installs, lists and removes SDK packages.
@MainActor
final class PackageManager: ObservableObject {
    static let shared = PackageManager()

    @Published private(set) var packages: [InstalledPackage] = []
    @Published private(set) var installing: Set<String> = []
    @Published var lastError: String?

    static let folder: URL = {
        let url = ProfileStore.folder.appendingPathComponent("Packages", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let settingsFolder: URL = {
        let url = ProfileStore.folder.appendingPathComponent("PackageSettings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Vendor packages replaced by integrations built into NexusDeck.
    nonisolated static let builtIn: Set<String> = ["com.avermedia.package.discord.toolbox", "com.avermedia.package.voicemodV3.toolbox", "com.avermedia.package.voicemodPlus.toolbox"]

    /// No online catalogue: packages are installed from file ("Importa widget").
    static let catalog: [CatalogPackage] = []

    init() { reload() }

    // MARK: Loading

    func reload() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        // Discord and Voicemod are built into NexusDeck now: their vendor packages are no longer used.
        for d in dirs where Self.builtIn.contains(d.lastPathComponent) { try? FileManager.default.removeItem(at: d) }
        packages = dirs.compactMap(Self.load).sorted { $0.name < $1.name }
    }

    func package(_ uuid: String) -> InstalledPackage? { packages.first { $0.uuid == uuid } }

    func widget(_ actionID: String) -> (InstalledPackage, PackageWidget)? {
        guard let (pkg, w) = Self.split(Self.resolveAlias(actionID)), let p = package(pkg), let widget = p.widgets.first(where: { $0.uuid == w }) else { return nil }
        return (p, widget)
    }

    /// Older package generations renamed in the store (same widgets, new identifiers).
    static let aliases: [(old: String, new: String)] = [
        ("com.avermedia.package.voicemodPlus.toolbox", "com.avermedia.package.voicemodV3.toolbox"),
        ("com.avermedia.widget.voicemodPlus.", "com.avermedia.widget.voicemodV3."),
    ]

    static func resolveAlias(_ actionID: String) -> String {
        var id = actionID
        for a in aliases { id = id.replacingOccurrences(of: a.old, with: a.new) }
        return id
    }

    /// Rewrites keys that point to renamed packages once the new package is installed.
    func migrate(_ store: ProfileStore) {
        func fix(_ k: inout KeyAssignment) {
            let r = Self.resolveAlias(k.actionID)
            if r != k.actionID, widget(r) != nil { k.actionID = r }
            for i in k.children.indices { fix(&k.children[i]) }
        }
        for p in store.library.hotkeyProfiles.indices {
            for i in store.library.hotkeyProfiles[p].keys.indices { fix(&store.library.hotkeyProfiles[p].keys[i]) }
        }
    }

    /// "pkg:<package>/<widget>"
    static func actionID(_ pkg: String, _ widget: String) -> String { "pkg:\(pkg)/\(widget)" }

    static func split(_ actionID: String) -> (String, String)? {
        guard actionID.hasPrefix("pkg:") else { return nil }
        let rest = actionID.dropFirst(4)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        return (String(rest[..<slash]), String(rest[rest.index(after: slash)...]))
    }

    private static func load(_ dir: URL) -> InstalledPackage? {
        let cfg = dir.appendingPathComponent("PackageConfig.json")
        guard let data = try? Data(contentsOf: cfg), let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let lang = (try? Data(contentsOf: dir.appendingPathComponent("lang/en.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let runtime = ((j["Runtime"] as? [String: Any])?["mac"] as? [String: Any]) ?? [:]
        let widgets: [PackageWidget] = ((j["Widgets"] as? [[String: Any]]) ?? []).map { w in
            let uuid = w["UUID"] as? String ?? ""
            let l = lang[uuid] as? [String: Any] ?? [:]
            let states = ((w["States"] as? [[String: Any]]) ?? []).enumerated().map { i, s in
                let lt = ((l["States"] as? [[String: Any]]).flatMap { i < $0.count ? $0[i]["Title"] as? String : nil })
                return (image: s["Image"] as? String ?? "", title: lt ?? s["Title"] as? String ?? s["Name"] as? String ?? "")
            }
            let layouts = ((w["Layouts"] as? [[String: Any]]) ?? []).map { (title: $0["Title"] as? String ?? "", width: $0["Width"] as? Int ?? 1, height: $0["Height"] as? Int ?? 1) }
            return PackageWidget(uuid: uuid,
                                 name: l["Name"] as? String ?? w["Name"] as? String ?? uuid,
                                 icon: w["Icon"] as? String ?? "",
                                 tooltip: l["Tooltip"] as? String ?? w["Tooltip"] as? String ?? "",
                                 propertyViewPath: w["PropertyViewPath"] as? String,
                                 multiActionSupported: w["MultiActionSupported"] as? Bool ?? true,
                                 titleEditable: w["TitleEditable"] as? Bool ?? true,
                                 iconEditable: w["IconEditable"] as? Bool ?? true,
                                 states: states.isEmpty ? [(image: w["Icon"] as? String ?? "", title: w["Name"] as? String ?? "")] : states,
                                 layouts: layouts)
        }
        return InstalledPackage(uuid: j["UUID"] as? String ?? dir.lastPathComponent,
                                name: lang["Name"] as? String ?? j["Name"] as? String ?? dir.lastPathComponent,
                                author: j["Author"] as? String ?? "",
                                description: lang["Description"] as? String ?? j["Description"] as? String ?? "",
                                version: j["Version"] as? String ?? "",
                                icon: j["Icon"] as? String ?? "",
                                directory: dir,
                                runtimeType: (runtime["type"] as? String ?? runtime["Type"] as? String ?? "web").lowercased(),
                                runtimeTarget: runtime["target"] as? String ?? runtime["Target"] as? String ?? "",
                                widgets: widgets)
    }

    // MARK: Install / remove

    func install(from url: URL) async {
        let key = url.absoluteString
        installing.insert(key)
        defer { installing.remove(key) }
        do {
            let file: URL
            if url.isFileURL { file = url } else {
                let (tmp, resp) = try await URLSession.shared.download(from: url)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw NSError(domain: "Store", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download non riuscito"]) }
                file = tmp
            }
            try await Task.detached { try Self.unpack(file) }.value
            reload()
            SDKHost.shared.packagesChanged()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Extracts a .creatorCentral (zip) archive into the packages folder.
    nonisolated static func unpack(_ archive: URL) throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", archive.path, tmp.path]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw NSError(domain: "Package", code: 2, userInfo: [NSLocalizedDescriptionKey: "Archivio non valido"]) }
        guard let root = FileManager.default.enumerator(at: tmp, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { $0.lastPathComponent == "PackageConfig.json" && !$0.path.contains("__MACOSX") })?
            .deletingLastPathComponent() else {
            throw NSError(domain: "Package", code: 3, userInfo: [NSLocalizedDescriptionKey: "PackageConfig.json mancante"])
        }
        let data = try Data(contentsOf: root.appendingPathComponent("PackageConfig.json"))
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let uuid = (j["UUID"] as? String) ?? root.lastPathComponent
        let dst = folder.appendingPathComponent(uuid, isDirectory: true)
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: root, to: dst)
        // Downloaded executables are quarantined; packages are run by the user's choice.
        let x = Process()
        x.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        x.arguments = ["-dr", "com.apple.quarantine", dst.path]
        try? x.run(); x.waitUntilExit()
    }

    func uninstall(_ uuid: String) {
        SDKHost.shared.stop(package: uuid)
        if let p = package(uuid) { try? FileManager.default.removeItem(at: p.directory) }
        reload()
    }

    // MARK: Package settings (global per package)

    func packageSettings(_ uuid: String) -> [String: Any] {
        let url = Self.settingsFolder.appendingPathComponent(uuid + ".json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    func setPackageSettings(_ uuid: String, _ settings: [String: Any]) {
        let url = Self.settingsFolder.appendingPathComponent(uuid + ".json")
        if let d = try? JSONSerialization.data(withJSONObject: settings) { try? d.write(to: url, options: .atomic) }
    }

    // MARK: Action catalogue integration

    var categories: [ActionCategory] {
        packages.map { p in
            ActionCategory(id: "pkg:" + p.uuid, title: p.name, symbol: "puzzlepiece.extension", actions: p.widgets.map { w in
                let layout = w.layouts.first
                return ActionDescriptor(id: Self.actionID(p.uuid, w.uuid), title: w.name, symbol: "puzzlepiece.extension.fill",
                                        kind: (layout.map { $0.width > 1 || $0.height > 1 } ?? false) ? .widget : .key,
                                        width: layout?.width ?? 1, height: layout?.height ?? 1,
                                        multiAction: w.multiActionSupported, stateTitles: w.states.map(\.title),
                                        iconFile: p.file(w.icon).path)
            })
        }
    }
}
