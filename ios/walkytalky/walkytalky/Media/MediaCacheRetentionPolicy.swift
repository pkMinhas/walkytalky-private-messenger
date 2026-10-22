import Foundation

/// Media is cached under `MediaStorage` (still encrypted) purely as a
/// performance optimization — `MediaDecryptor` already re-downloads on
/// demand whenever a cached file is missing, then decrypts with the
/// still-Keychain-resident conversation key. That makes "evict after N days,
/// re-download on demand" a safe default: nothing is lost, just re-fetched
/// next time it's viewed.
enum MediaCacheRetentionPolicy {
    /// 30 days
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    /// Deletes cached media files last modified more than `maxAge` ago,
    /// inside every conversation folder. Call once per app launch.
    static func evictExpiredFiles(maxAge: TimeInterval = maxAge, now: Date = Date()) {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: MediaStorage.directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        let cutoff = now.addingTimeInterval(-maxAge)
        for folder in folders where MediaStorage.isDirectory(folder) {
            guard let files = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in files {
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = values.contentModificationDate,
                      modified < cutoff
                else { continue }
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
