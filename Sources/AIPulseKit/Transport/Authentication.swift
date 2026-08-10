import Foundation
import Security

/// Generates and stores the local API bearer token in the user's Keychain.
public struct KeychainTokenStore: Sendable {
    public let service: String
    public let account: String

    public init(service: String = "me.leog.aipulse", account: String = "local-api-token") {
        self.service = service
        self.account = account
    }

    /// Returns the persisted token, creating one on first launch. If the
    /// Keychain is unavailable (denied prompt, headless session) an
    /// ephemeral token is returned so the server still starts — clients
    /// learn the current token through the handshake file either way.
    public func loadOrCreate() -> String {
        if let existing = load() {
            return existing
        }
        let token = Self.generateToken()
        store(token)
        return token
    }

    private func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    private func store(_ token: String) {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "AI Pulse local API token",
            kSecValueData as String: Data(token.utf8),
        ]
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// 256-bit random token, base64url without padding.
    public static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // SystemRandomNumberGenerator is itself cryptographically secure.
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Connection details the `aipulse` CLI reads so users never paste tokens
/// into shell commands. Written by the app, owner-read/write only (0600).
public struct CLIHandshake: Codable, Sendable, Equatable {
    public var port: Int
    public var token: String

    public init(port: Int, token: String) {
        self.port = port
        self.token = token
    }
}

public enum CLIHandshakeFile {
    public static let environmentOverride = "AIPULSE_CONFIG"

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment[environmentOverride] {
            return URL(fileURLWithPath: override)
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("AIPulse", isDirectory: true)
            .appendingPathComponent("cli.json")
    }

    public static func write(_ handshake: CLIHandshake, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(handshake)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func read(from url: URL) -> CLIHandshake? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CLIHandshake.self, from: data)
    }
}
