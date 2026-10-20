import Foundation
import Security

/// Thin wrapper around the Keychain Services API for storing small secrets
/// (device install ID, passcode hash/salt, conversation keys) that must
/// never be written to Firestore or UserDefaults.
enum KeychainService {
    static func save(_ data: Data, account: String, service: String = defaultService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(account: String, service: String = defaultService) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String, service: String = defaultService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Deletes every item in `service` whose account name starts with
    /// `prefix`. Used for families of items keyed by id (e.g. per-conversation
    /// keys) that have no fixed list of account names to delete one by one.
    static func deleteAll(accountPrefix prefix: String, service: String = defaultService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]]
        else { return }

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(prefix) else { continue }
            delete(account: account, service: service)
        }
    }

    static func saveString(_ string: String, account: String, service: String = defaultService) {
        save(Data(string.utf8), account: account, service: service)
    }

    static func loadString(account: String, service: String = defaultService) -> String? {
        guard let data = load(account: account, service: service) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static let defaultService = "com.withpreet.walkytalky"
}
