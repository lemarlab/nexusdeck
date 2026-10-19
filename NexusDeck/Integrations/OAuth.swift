import Foundation
import Network
import CryptoKit
import AppKit

struct OAuthToken: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpired: Bool { Date() > expiresAt.addingTimeInterval(-60) }
}

enum OAuthError: LocalizedError {
    case missingClientID, denied, server(String)
    var errorDescription: String? {
        switch self {
        case .missingClientID: "Inserisci il Client ID nelle impostazioni dell'integrazione."
        case .denied: "Autorizzazione negata."
        case .server(let s): s
        }
    }
}

enum OAuth {
    static func store(_ t: OAuthToken?, account: String) {
        Keychain.set(t.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }, for: account)
    }

    static func load(account: String) -> OAuthToken? {
        Keychain.get(account).flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(OAuthToken.self, from: $0) }
    }

    static func form(_ url: String, _ params: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = c.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func token(from j: [String: Any], keepRefresh: String? = nil) -> OAuthToken? {
        guard let at = j["access_token"] as? String else { return nil }
        let exp = (j["expires_in"] as? Double) ?? Double(j["expires_in"] as? Int ?? 3600)
        return OAuthToken(accessToken: at, refreshToken: (j["refresh_token"] as? String) ?? keepRefresh, expiresAt: Date().addingTimeInterval(exp))
    }

    /// RFC 8628 device authorization flow. `present` receives the user code and verification URL.
    static func deviceFlow(deviceURL: String, tokenURL: String, clientID: String, clientSecret: String? = nil, scopes: String,
                           present: @MainActor (String, URL) -> Void) async throws -> OAuthToken {
        guard !clientID.isEmpty else { throw OAuthError.missingClientID }
        let start = try await form(deviceURL, ["client_id": clientID, "scope": scopes, "scopes": scopes])
        guard let deviceCode = start["device_code"] as? String, let userCode = start["user_code"] as? String,
              let verify = (start["verification_uri"] as? String) ?? (start["verification_url"] as? String), let vURL = URL(string: verify) else {
            throw OAuthError.server(start["message"] as? String ?? start["error_description"] as? String ?? "Risposta non valida")
        }
        await present(userCode, vURL)
        NSWorkspace.shared.open(vURL)
        var interval = Double(start["interval"] as? Int ?? 5)
        let deadline = Date().addingTimeInterval(Double(start["expires_in"] as? Int ?? 600))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            var p = ["client_id": clientID, "device_code": deviceCode, "grant_type": "urn:ietf:params:oauth:grant-type:device_code", "scopes": scopes]
            if let clientSecret { p["client_secret"] = clientSecret }
            let r = try await form(tokenURL, p)
            if let t = token(from: r) { return t }
            let err = (r["error"] as? String) ?? (r["message"] as? String) ?? ""
            if err.contains("slow_down") { interval += 5; continue }
            if err.contains("pending") { continue }
            if err.contains("denied") { throw OAuthError.denied }
            if !err.isEmpty { throw OAuthError.server(err) }
        }
        throw OAuthError.server("Codice scaduto")
    }

    static func refresh(tokenURL: String, clientID: String, clientSecret: String? = nil, token: OAuthToken) async throws -> OAuthToken {
        guard let rt = token.refreshToken else { throw OAuthError.denied }
        var p = ["client_id": clientID, "grant_type": "refresh_token", "refresh_token": rt]
        if let clientSecret { p["client_secret"] = clientSecret }
        let r = try await form(tokenURL, p)
        guard let t = Self.token(from: r, keepRefresh: rt) else { throw OAuthError.server(r["message"] as? String ?? "Refresh fallito") }
        return t
    }

    /// Authorization code + PKCE with a loopback redirect (used by Spotify).
    static func pkceLoopback(authURL: String, tokenURL: String, clientID: String, scopes: String, port: UInt16) async throws -> OAuthToken {
        guard !clientID.isEmpty else { throw OAuthError.missingClientID }
        let verifier = (0..<64).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".randomElement()! }.map(String.init).joined()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let redirect = "http://127.0.0.1:\(port)/callback"
        var c = URLComponents(string: authURL)!
        c.queryItems = [.init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"), .init(name: "redirect_uri", value: redirect),
                        .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: challenge), .init(name: "scope", value: scopes)]
        let code = try await LoopbackServer.waitForCode(port: port) { NSWorkspace.shared.open(c.url!) }
        let r = try await form(tokenURL, ["client_id": clientID, "grant_type": "authorization_code", "code": code, "redirect_uri": redirect, "code_verifier": verifier])
        guard let t = token(from: r) else { throw OAuthError.server(r["error_description"] as? String ?? "Token non ricevuto") }
        return t
    }
}

/// Minimal one-shot HTTP listener capturing `?code=` from an OAuth redirect.
enum LoopbackServer {
    static func waitForCode(port: UInt16, onReady: @escaping () -> Void) async throws -> String {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        return try await withCheckedThrowingContinuation { cont in
            var done = false
            listener.newConnectionHandler = { conn in
                conn.start(queue: .main)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    let req = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let line = req.split(separator: "\r\n").first.map(String.init) ?? ""
                    let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                    let items = URLComponents(string: "http://x" + path)?.queryItems ?? []
                    let body = "<html><body style='font-family:-apple-system'><h2>NexusDeck</h2><p>Puoi chiudere questa finestra.</p></body></html>"
                    let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                    guard !done, path.hasPrefix("/callback") else { return }
                    done = true
                    listener.cancel()
                    if let code = items.first(where: { $0.name == "code" })?.value { cont.resume(returning: code) }
                    else { cont.resume(throwing: OAuthError.denied) }
                }
            }
            listener.stateUpdateHandler = { s in
                if case .ready = s { onReady() }
                if case .failed(let e) = s, !done { done = true; cont.resume(throwing: e) }
            }
            listener.start(queue: .main)
        }
    }
}
