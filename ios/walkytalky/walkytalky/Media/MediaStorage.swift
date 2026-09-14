import Foundation

/// App-private (sandboxed) storage for media: plaintext captures pending
/// encryption+upload, and decrypted files ready to render (Phase 6). Never
/// the system Photos library — that only happens via explicit "Save to
/// Gallery" (Phase 7).
enum MediaStorage {
    static let directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func fileURL(for messageId: String) -> URL {
        directory.appendingPathComponent(messageId)
    }

    @discardableResult
    static func write(_ data: Data, messageId: String) throws -> URL {
        let url = fileURL(for: messageId)
        try data.write(to: url, options: .atomic)
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
}
