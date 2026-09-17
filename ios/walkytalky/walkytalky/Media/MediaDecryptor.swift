import FirebaseStorage
import UIKit

/// Shared download-decrypt-cache pipeline for a media message, used by both
/// the inline chat bubble (`MediaMessageView`) and the media gallery grid so
/// the two never diverge. Caches decrypted bytes in `MediaStorage` keyed by
/// message id, so a photo already opened in one place decrypts once.
enum MediaDecryptor {
    static func decryptedImage(for message: Message, conversationId: String) async -> UIImage? {
        guard let messageId = message.id else { return nil }

        if let cached = MediaStorage.read(messageId: messageId), let image = UIImage(data: cached) {
            return image
        }

        guard let storagePath = message.storagePath,
              let nonce = message.nonce,
              let keyVersion = message.keyVersion,
              let key = ConversationKeyStore.key(conversationId: conversationId, keyVersion: keyVersion)
        else {
            return nil
        }

        do {
            let ref = Storage.storage().reference(withPath: storagePath)
            let downloaded = try await ref.data(maxSize: 25 * 1024 * 1024)
            let decrypted = try MediaCrypto.decrypt(downloaded, nonceBase64: nonce, key: key)
            try MediaStorage.write(decrypted, messageId: messageId)
            return UIImage(data: decrypted)
        } catch {
            return nil
        }
    }
}
