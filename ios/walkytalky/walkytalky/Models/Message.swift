import FirebaseFirestore
import Foundation

enum MessageType: String, Codable {
    case text
    case image
    case gif
}

/// Mirrors a `conversations/{id}/messages/{messageId}` Firestore document.
/// For `.text` messages, `text` holds base64 AES-256-GCM ciphertext (not
/// plaintext) alongside `nonce`/`keyVersion` — same scheme as media, reusing
/// `MediaCrypto`/`ConversationKeyStore`. `storagePath` stays media-only.
struct Message: Identifiable, Codable {
    @DocumentID var id: String?
    var senderId: String
    var type: MessageType
    var text: String?
    var storagePath: String?
    var nonce: String?
    var keyVersion: Int?
    @ServerTimestamp var createdAt: Date?
    var deletedFor: [String] = []
    var deletedForEveryone: Bool = false
    @ServerTimestamp var deletedAt: Date?
}

enum MessageEncryptionError: LocalizedError {
    case notPaired

    var errorDescription: String? {
        switch self {
        case .notPaired: "Not paired with this contact yet."
        }
    }
}

extension Message {
    /// Encrypts a plaintext string with the conversation's current key, for
    /// use as a `.text` message's `text`/`nonce`/`keyVersion` fields.
    static func encryptText(_ plaintext: String, conversationId: String) throws -> (textBase64: String, nonceBase64: String, keyVersion: Int) {
        guard let key = ConversationKeyStore.currentKey(conversationId: conversationId),
              let keyVersion = ConversationKeyStore.currentVersion(conversationId: conversationId)
        else {
            throw MessageEncryptionError.notPaired
        }
        let encrypted = try MediaCrypto.encrypt(Data(plaintext.utf8), key: key)
        return (encrypted.uploadData.base64EncodedString(), encrypted.nonceBase64, keyVersion)
    }

    /// Decrypts a `.text` message's content for display. Messages sent
    /// before text encryption existed have no `nonce`/`keyVersion` and are
    /// rendered as their stored plaintext, so old data doesn't break.
    func decryptedText(conversationId: String) -> String {
        guard let nonce, let keyVersion else {
            return text ?? ""
        }
        guard let textBase64 = text,
              let cipherData = Data(base64Encoded: textBase64),
              let key = ConversationKeyStore.key(conversationId: conversationId, keyVersion: keyVersion),
              let plaintext = try? MediaCrypto.decrypt(cipherData, nonceBase64: nonce, key: key),
              let string = String(data: plaintext, encoding: .utf8)
        else {
            return "🔒 Can't decrypt this message"
        }
        return string
    }
}
