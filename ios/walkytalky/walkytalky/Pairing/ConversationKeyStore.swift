import CryptoKit
import Foundation

/// Per-conversation symmetric keys derived via ECDH+HKDF during pairing.
/// Keychain schema: `{conversationId, keyVersion, key}`. Re-pairing bumps
/// `keyVersion` and discards the previous version's key material — per
/// spec, old messages encrypted under a discarded version become
/// permanently undecryptable (Phase 6 shows a placeholder for those).
enum ConversationKeyStore {
    private static func keyAccount(conversationId: String, keyVersion: Int) -> String {
        "convKey_\(conversationId)_v\(keyVersion)"
    }

    private static func versionAccount(conversationId: String) -> String {
        "convKeyVersion_\(conversationId)"
    }

    static func currentVersion(conversationId: String) -> Int? {
        guard let string = KeychainService.loadString(account: versionAccount(conversationId: conversationId)) else {
            return nil
        }
        return Int(string)
    }

    static func key(conversationId: String, keyVersion: Int) -> SymmetricKey? {
        guard let data = KeychainService.load(account: keyAccount(conversationId: conversationId, keyVersion: keyVersion)) else {
            return nil
        }
        return SymmetricKey(data: data)
    }

    static func currentKey(conversationId: String) -> SymmetricKey? {
        guard let version = currentVersion(conversationId: conversationId) else { return nil }
        return key(conversationId: conversationId, keyVersion: version)
    }

    /// Deletes every conversation's key material and version marker, so
    /// nothing previously decrypted can be decrypted again on this device.
    static func deleteAll() {
        KeychainService.deleteAll(accountPrefix: "convKey_")
        KeychainService.deleteAll(accountPrefix: "convKeyVersion_")
    }

    /// Stores a freshly derived key as the new current version, discarding
    /// the previous version's key material (re-pair semantics).
    static func store(conversationId: String, keyVersion: Int, key: SymmetricKey) {
        if let previousVersion = currentVersion(conversationId: conversationId), previousVersion != keyVersion {
            KeychainService.delete(account: keyAccount(conversationId: conversationId, keyVersion: previousVersion))
        }
        key.withUnsafeBytes { rawBuffer in
            KeychainService.save(Data(rawBuffer), account: keyAccount(conversationId: conversationId, keyVersion: keyVersion))
        }
        KeychainService.saveString(String(keyVersion), account: versionAccount(conversationId: conversationId))
    }
}
