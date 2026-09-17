import FirebaseStorage
import UIKit

/// Shared download-decrypt-cache pipeline for a media message, used by both
/// the inline chat bubble (`MediaMessageView`) and the media gallery grid so
/// the two never diverge. Caches decrypted bytes in `MediaStorage` keyed by
/// message id, so a photo already opened in one place decrypts once.
enum MediaDecryptor {
    static func decryptedMedia(for message: Message, conversationId: String) async -> DecodedMedia? {
        guard let messageId = message.id else { return nil }

        if let cached = MediaStorage.read(messageId: messageId), let media = decode(cached, type: message.type) {
            return media
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
            return decode(decrypted, type: message.type)
        } catch {
            return nil
        }
    }

    /// GIF-typed messages get every frame via `GIFDecoder`, falling back to
    /// a single-frame decode if that somehow fails (corrupt/truncated data)
    /// — still better than showing nothing. Everything else is a static
    /// image, one frame from the start.
    private static func decode(_ data: Data, type: MessageType) -> DecodedMedia? {
        if type == .gif, let animated = GIFDecoder.decode(data) {
            return animated
        }
        return UIImage(data: data).map(DecodedMedia.single)
    }
}
