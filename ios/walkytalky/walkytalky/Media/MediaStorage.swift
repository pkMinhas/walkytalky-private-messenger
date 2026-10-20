import Foundation

/// App-private (sandboxed) storage for media: plaintext captures pending
/// encryption+upload, and decrypted files ready to render (Phase 6). Never
/// the system Photos library — that only happens via explicit "Save to
/// Gallery" (Phase 7).
///
/// Everything here is plaintext, so it's written with complete file
/// protection: unreadable whenever the device is locked, not just before
/// first unlock (the iOS default).
///
/// `nonisolated`: these are plain `FileManager` calls with no shared
/// mutable state, and the project's `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor` setting would otherwise pin them to the main actor.
/// `ConversationsService` runs `deleteConversations` in a detached task so
/// deleting a conversation's media never stalls the UI.
nonisolated enum MediaStorage {
    static let directory: URL = {
        let fileManager = FileManager.default
        let url = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Media", isDirectory: true)
        try? fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        // createDirectory leaves an already-existing directory's attributes
        // alone, so a directory created by an older build is upgraded here.
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        return url
    }()

    /// One folder per conversation (`Media/<conversationId>/<messageId>`),
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

    /// Builds before per-conversation folders cached files flat, as
    /// `Media/<messageId>`, with nothing recording which conversation each
    /// one came from, so they can never be matched to a removed
    /// conversation. Since this is only a cache, they're deleted instead:
    /// media for conversations the user is still in is re-downloaded and
    /// re-decrypted into the new layout the next time it's viewed. Safe to
    /// run every launch, since nothing writes flat files anymore.
    static func purgeLegacyFlatFiles(root: URL = directory) {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for item in items where !isDirectory(item) {
            try? fileManager.removeItem(at: item)
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// Removes every cached file and conversation folder (and any leftover
    /// share copy). The top-level directory itself stays, since `directory`
    /// only creates it once.
    static func deleteAll() {
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
        deleteShareFiles()
    }

    // MARK: - Share copy

    /// The temp file handed to `ShareLink` by the media viewer, named
    /// `walkytalky-image.<jpg|gif>` so the receiving app sees a real
    /// filename and the original format.
    static func shareFileURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("walkytalky-image.\(fileExtension)")
    }

    @discardableResult
    static func writeShareFile(_ data: Data, fileExtension: String) throws -> URL {
        let url = shareFileURL(fileExtension: fileExtension)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func deleteShareFiles() {
        for fileExtension in ["jpg", "gif"] {
            try? FileManager.default.removeItem(at: shareFileURL(fileExtension: fileExtension))
        }
    }
}
