import FirebaseStorage
import UIKit

/// Shared download-decrypt-cache pipeline for a media message, used by the
/// inline chat bubble (`MediaMessageView`), the media gallery grid and the
/// fullscreen pager so they never diverge. Looks in three places, in order:
///
/// 1. `MediaMemoryCache`: decrypted bytes, memory only.
/// 2. `MediaStorage`: the ciphertext as downloaded, decrypted here.
/// 3. Firebase Storage: downloaded, cached encrypted on disk, then decrypted.
///
/// Plaintext never reaches disk. The key is checked on every disk or
/// network path, so media from a re-paired (old key discarded) or removed
/// conversation can't be decrypted from the cache either.
enum MediaDecryptor {
    static func decryptedMedia(for message: Message, conversationId: String) async -> DecodedMedia? {
        guard let data = await decryptedData(for: message, conversationId: conversationId) else { return nil }
        return decode(data, type: message.type)
    }

    /// The decrypted file bytes themselves: what the share sheet hands
    /// out, and what `decryptedMedia` decodes for display.
    static func decryptedData(for message: Message, conversationId: String) async -> Data? {
        guard let messageId = message.id else { return nil }

        if let cached = MediaMemoryCache.shared.data(messageId: messageId, conversationId: conversationId) {
            return cached
        }

        guard let storagePath = message.storagePath,
              let nonce = message.nonce,
              let keyVersion = message.keyVersion,
              let key = ConversationKeyStore.key(conversationId: conversationId, keyVersion: keyVersion)
        else {
            return nil
        }

        // A cached copy that fails to decrypt (truncated write, corruption,
        // tampering: GCM's tag check catches all three) is discarded and
        // fetched again rather than shown as undecryptable.
        if let encrypted = MediaStorage.read(messageId: messageId, conversationId: conversationId) {
            if let decrypted = try? MediaCrypto.decrypt(encrypted, nonceBase64: nonce, key: key) {
                MediaMemoryCache.shared.store(decrypted, messageId: messageId, conversationId: conversationId)
                return decrypted
            }
            MediaStorage.delete(messageId: messageId, conversationId: conversationId)
        }

        do {
            let ref = Storage.storage().reference(withPath: storagePath)
            let downloaded = try await ref.data(maxSize: 25 * 1024 * 1024)
            let decrypted = try MediaCrypto.decrypt(downloaded, nonceBase64: nonce, key: key)
            // Only cached once it's proven to decrypt, so a bad download
            // never sits on disk. A failed write (e.g. the device locked
            // mid-download, under complete file protection) still shows the
            // media; it's just fetched again next time.
            _ = try? MediaStorage.write(downloaded, messageId: messageId, conversationId: conversationId)
            MediaMemoryCache.shared.store(decrypted, messageId: messageId, conversationId: conversationId)
            return decrypted
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
