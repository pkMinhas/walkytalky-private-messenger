import Foundation

/// App-private (sandboxed) disk cache of media exactly as downloaded from
/// Storage: still encrypted (`ciphertext || tag`), never plaintext. Decrypted
/// bytes only ever live in `MediaMemoryCache`; `MediaDecryptor` decrypts from
/// here on demand with the Keychain-resident conversation key, so a cached
/// file is useless without that key and becomes unreadable the moment the
/// key is deleted (re-pair, removal from the conversation, sign-out).
///
/// Files are still written with complete file protection as defense in
/// depth: unreadable whenever the device is locked, not just before first
/// unlock (the iOS default).
///
/// `nonisolated`: these are plain `FileManager` calls with no shared
/// mutable state, and the project's `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor` setting would otherwise pin them to the main actor.
/// `ConversationsService` runs `deleteConversations` in a detached task so
/// deleting a conversation's media never stalls the UI.
nonisolated enum MediaStorage {
    static let directory: URL = {
        let fileManager = FileManager.default
        let url = cachesDirectory.appendingPathComponent("EncryptedMedia", isDirectory: true)
        try? fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        return url
    }()

    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    /// One folder per conversation (`EncryptedMedia/<conversationId>/<messageId>`),
    /// so everything cached for a conversation can be removed in one go once
    /// this user is no longer in it. Firestore document ids can't contain
    /// "/" or be "." / "..", so an id is always a safe single path component.
    static func conversationDirectory(_ conversationId: String) -> URL {
        directory.appendingPathComponent(conversationId, isDirectory: true)
    }

    static func fileURL(for messageId: String, conversationId: String) -> URL {
        conversationDirectory(conversationId).appendingPathComponent(messageId)
    }

    @discardableResult
    static func write(_ data: Data, messageId: String, conversationId: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: conversationDirectory(conversationId),
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        let url = fileURL(for: messageId, conversationId: conversationId)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func read(messageId: String, conversationId: String) -> Data? {
        try? Data(contentsOf: fileURL(for: messageId, conversationId: conversationId))
    }

    static func delete(messageId: String, conversationId: String) {
        try? FileManager.default.removeItem(at: fileURL(for: messageId, conversationId: conversationId))
    }

    static func exists(messageId: String, conversationId: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: messageId, conversationId: conversationId).path)
    }

    /// Removes the cache folder of every conversation not in
    /// `activeConversationIds`, i.e. ones this user was removed from or that
    /// were deleted on the server. Only call this with a server-confirmed
    /// list: a partial or stale one would wipe media that's still valid.
    static func deleteConversations(notIn activeConversationIds: Set<String>, root: URL = directory) {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for item in items where isDirectory(item) && !activeConversationIds.contains(item.lastPathComponent) {
            try? fileManager.removeItem(at: item)
        }
    }

    /// Removes every cached file and conversation folder. The top-level
    /// directory itself stays, since `directory` only creates it once.
    static func deleteAll(root: URL = directory) {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for item in items {
            try? fileManager.removeItem(at: item)
        }
    }

    /// Builds before the encrypted cache kept *decrypted* media under
    /// `Caches/Media` (flat `<messageId>` files, later per-conversation
    /// folders). None of it is needed anymore and all of it is plaintext,
    /// so the whole folder goes, along with the share copy those builds
    /// left in `tmp`. Nothing is lost: it was only ever a cache, so media
    /// is re-downloaded into the encrypted cache the next time it's viewed.
    /// Safe to run every launch, since nothing writes there anymore.
    static func removeLegacyPlaintextCache(cachesRoot: URL = cachesDirectory, tmpRoot: URL = FileManager.default.temporaryDirectory) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: cachesRoot.appendingPathComponent("Media", isDirectory: true))
        for fileExtension in ["jpg", "gif"] {
            try? fileManager.removeItem(at: tmpRoot.appendingPathComponent("walkytalky-image.\(fileExtension)"))
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
