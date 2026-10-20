import Foundation
import Security

/// Secrets of the integrations (OBS password, tokens, API keys).
///
/// They are kept in a file readable only by the user (`Secrets.plist`, permissions 600) in NexusDeck's folder.
/// The macOS keychain ties items to the exact code signature of the app: NexusDeck is not signed with a
/// developer certificate, so every new build or update looked like a different app and macOS asked for the
/// keychain password at every launch. Older items are moved from the keychain once.
enum Keychain {
    private static let service = "com.nexusdeck.lemarlab"
    private static let url = ProfileStore.folder.appendingPathComponent("Secrets.plist")
    private static let lock = NSLock()
    private static var cache: [String: String]?

    /// Accounts that older versions stored in the keychain.
    private static let legacyAccounts = ["obs", "streamlabs", "discord.clientID", "discord.clientSecret", "discord.accessToken",
                                         "discord.refreshToken", "voicemod.apiKey", "twitch", "youtube", "spotify"]

    static func set(_ value: String?, for account: String) {
        lock.lock(); defer { lock.unlock() }
        var all = load()
        if let value, !value.isEmpty { all[account] = value } else { all[account] = nil }
        save(all)
    }

    static func get(_ account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return load()[account]
    }

    private static func load() -> [String: String] {
        if let cache { return cache }
        var all = (try? Data(contentsOf: url)).flatMap { try? PropertyListDecoder().decode([String: String].self, from: $0) } ?? [:]
        if !UserDefaults.standard.bool(forKey: "secrets.migrated") {
            UserDefaults.standard.set(true, forKey: "secrets.migrated")
            for a in legacyAccounts where all[a] == nil {
                if let v = keychainGet(a) { all[a] = v; keychainDelete(a) }
            }
            cache = all
            save(all)
        }
        cache = all
        return all
    }

    private static func save(_ all: [String: String]) {
        cache = all
        guard let d = try? PropertyListEncoder().encode(all) else { return }
        try? d.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: Old keychain items (read once, then removed)

    private static func keychainGet(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func keychainDelete(_ account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}
