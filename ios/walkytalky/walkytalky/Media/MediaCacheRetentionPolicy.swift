import Foundation

/// Decrypted media is cached under `MediaStorage` purely as a performance
/// optimization — `MediaMessageView` already re-downloads and re-decrypts on
/// demand whenever a cached file is missing, using the still-Keychain-resident
/// conversation key. That makes "evict after N days, re-decrypt on demand"
/// a safe default: nothing is lost, just re-fetched next time it's viewed.
enum MediaCacheRetentionPolicy {
    /// 1 day
    static let maxAge: TimeInterval = 1 * 24 * 60 * 60

    /// Deletes cached decrypted media files last modified more than `maxAge`
    /// ago, inside every conversation folder. Call once per app launch.
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
