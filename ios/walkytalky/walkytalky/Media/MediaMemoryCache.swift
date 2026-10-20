import Foundation

/// The only place decrypted media bytes are kept between views: in memory,
/// never on disk (`MediaStorage` only ever holds ciphertext). Holds the
/// decrypted file bytes (still JPEG/GIF-compressed, a few MB each) rather
/// than decoded bitmaps, which would be ~33 MB per 4K frame.
///
/// Emptied whenever the app goes to the background, which is also when it
/// locks, so plaintext only exists while the app is unlocked and in use.
/// `NSCache` also drops entries on its own under memory pressure; a miss
/// just means decrypting again from the encrypted disk copy.
///
/// `nonisolated` + `@unchecked Sendable`: `NSCache` is documented as safe
/// to use from multiple threads, it just isn't annotated `Sendable`.
nonisolated final class MediaMemoryCache: @unchecked Sendable {
    static let shared = MediaMemoryCache()

    /// 100 MB of decrypted bytes: roughly 20-50 photos at the app's 4K /
    /// JPEG 95% upload size.
    static let costLimit = 100 * 1024 * 1024

    private let cache = NSCache<NSString, NSData>()

    init(costLimit: Int = MediaMemoryCache.costLimit) {
        cache.totalCostLimit = costLimit
    }

    private func key(messageId: String, conversationId: String) -> NSString {
        "\(conversationId)/\(messageId)" as NSString
    }

    func data(messageId: String, conversationId: String) -> Data? {
        cache.object(forKey: key(messageId: messageId, conversationId: conversationId)) as Data?
    }

    func store(_ data: Data, messageId: String, conversationId: String) {
        cache.setObject(data as NSData, forKey: key(messageId: messageId, conversationId: conversationId), cost: data.count)
    }

    func remove(messageId: String, conversationId: String) {
        cache.removeObject(forKey: key(messageId: messageId, conversationId: conversationId))
    }

    /// `NSCache` can't list its keys, so dropping one conversation's entries
    /// (removal, re-pair) empties everything instead. Those events are rare,
    /// and a miss only costs a local decrypt.
    func removeAll() {
        cache.removeAllObjects()
    }
}
