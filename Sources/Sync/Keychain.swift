import Foundation
import Security

/// Secrets live in the Keychain, never in UserDefaults or the data folder: the hub's token (this service) and the Claude API key
/// (`Keychain.claude`).
enum Keychain {
    static let service = "app.nexus.mobile.sync"
    static let claude = "app.nexus.mobile.claude"

    static func get(_ account: String, service: String = Keychain.service) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves (or, for an empty value, removes) the item. Readable after the first unlock, so a sync in the background works.
    @discardableResult
    static func set(_ value: String, for account: String, service: String = Keychain.service) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        if value.isEmpty { return true }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
