import Foundation

/// App-private (sandboxed) storage for media: plaintext captures pending
/// encryption+upload, and decrypted files ready to render (Phase 6). Never
/// the system Photos library — that only happens via explicit "Save to
/// Gallery" (Phase 7).
///
/// Everything here is plaintext, so it's written with complete file
/// protection: unreadable whenever the device is locked, not just before
/// first unlock (the iOS default).
enum MediaStorage {
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
        // alone, so files cached before complete protection was introduced
        // are upgraded here once per launch.
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        if let files = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
            }
        }
        return url
    }()

    static func fileURL(for messageId: String) -> URL {
        directory.appendingPathComponent(messageId)
    }

    @discardableResult
    static func write(_ data: Data, messageId: String) throws -> URL {
        let url = fileURL(for: messageId)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func read(messageId: String) -> Data? {
        try? Data(contentsOf: fileURL(for: messageId))
    }

    static func delete(messageId: String) {
        try? FileManager.default.removeItem(at: fileURL(for: messageId))
    }

    static func exists(messageId: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: messageId).path)
    }

    /// Removes every cached file (and any leftover share copy). The
    /// directory itself stays, since `directory` only creates it once.
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
