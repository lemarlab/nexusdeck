import Foundation
import AppKit

/// Checks the latest GitHub release and installs it: downloads the DMG, replaces the app bundle, relaunches.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "lemarlab/nexusdeck"

    enum State: Equatable {
        case idle, checking, upToDate, available(String), downloading, installing, failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var notes = ""
    private var dmgURL: URL?

    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    var latestVersion: String? { if case .available(let v) = state { return v }; return nil }

    /// How often NexusDeck looks for updates on its own.
    enum Frequency: Int, CaseIterable, Identifiable {
        case launch = 0, daily, weekly, monthly, never
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .launch: "A ogni avvio"
            case .daily: "Ogni giorno"
            case .weekly: "Ogni settimana"
            case .monthly: "Ogni mese"
            case .never: "Mai"
            }
        }
        var interval: TimeInterval? {
            switch self {
            case .launch: nil
            case .daily: 86_400
            case .weekly: 7 * 86_400
            case .monthly: 30 * 86_400
            case .never: nil
            }
        }
    }

    @Published var frequency: Frequency = Frequency(rawValue: UserDefaults.standard.integer(forKey: "updater.frequency")) ?? .launch {
        didSet { UserDefaults.standard.set(frequency.rawValue, forKey: "updater.frequency") }
    }
    private let lastCheckKey = "updater.lastCheck"
    private var timer: Timer?

    /// Automatic checks: at launch, then (while the app stays open) whenever the chosen interval has passed.
    func startAutomaticChecks() {
        if frequency == .launch { Task { await check() } } else { checkIfDue() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard let interval = frequency.interval else { return }
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last >= interval else { return }
        Task { await check() }
    }

    func check() async {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        state = .checking
        do {
            // All releases (pre-releases included): the newest version that has a DMG.
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases?per_page=30")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { state = .failed("Impossibile leggere le release"); return }
            var best: (version: String, dmg: URL, json: [String: Any])?
            for r in list where (r["draft"] as? Bool) != true {
                guard let tag = r["tag_name"] as? String else { continue }
                let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let assets = r["assets"] as? [[String: Any]] ?? []
                guard let dmg = assets.compactMap({ a -> URL? in
                    guard let n = a["name"] as? String, n.lowercased().hasSuffix(".dmg"), let u = a["browser_download_url"] as? String else { return nil }
                    return URL(string: u)
                }).first else { continue }
                if best == nil || Self.isNewer(version, than: best!.version) { best = (version, dmg, r) }
            }
            guard let best else { state = .upToDate; return }
            dmgURL = best.dmg
            let json = best.json
            let version = best.version
            notes = json["body"] as? String ?? ""
            state = Self.isNewer(version, than: Self.currentVersion) && dmgURL != nil ? .available(version) : .upToDate
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Downloads the DMG, replaces the running app with the one inside and relaunches.
    func install() async {
        guard let dmgURL else { return }
        state = .downloading
        do {
            let (tmp, resp) = try await URLSession.shared.download(from: dmgURL)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { state = .failed("Download non riuscito"); return }
            state = .installing
            let appPath = Bundle.main.bundlePath
            try await Task.detached { try Self.replaceApp(dmg: tmp, at: appPath) }.value
            relaunch(appPath)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else { throw NSError(domain: "Updater", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: s]) }
        return s
    }

    nonisolated private static func replaceApp(dmg: URL, at appPath: String) throws {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("NexusDeckUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        _ = try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let newApp = mount.appendingPathComponent("NexusDeck.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else {
            throw NSError(domain: "Updater", code: 1, userInfo: [NSLocalizedDescriptionKey: "NexusDeck.app non trovata nel DMG"])
        }
        // Copy next to the current app, then swap.
        let staged = URL(fileURLWithPath: appPath).deletingLastPathComponent().appendingPathComponent(".NexusDeck-update.app")
        try? FileManager.default.removeItem(at: staged)
        _ = try run("/usr/bin/ditto", [newApp.path, staged.path])
        _ = try? run("/usr/bin/xattr", ["-cr", staged.path])
        let old = URL(fileURLWithPath: appPath)
        _ = try FileManager.default.replaceItemAt(old, withItemAt: staged)
    }

    private func relaunch(_ appPath: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1.5; /usr/bin/open \"\(appPath)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}
