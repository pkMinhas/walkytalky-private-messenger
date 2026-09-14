import Foundation

/// Decrypted media is cached under `MediaStorage` purely as a performance
/// optimization — `MediaMessageView` already re-downloads and re-decrypts on
/// demand whenever a cached file is missing, using the still-Keychain-resident
/// conversation key. That makes "evict after N days, re-decrypt on demand"
/// a safe default: nothing is lost, just re-fetched next time it's viewed.
enum MediaCacheRetentionPolicy {
    /// TODO(HUMAN): confirm this window — not specified anywhere in the task
    /// list, defaulting to 30 days.
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    /// Deletes cached decrypted media files last modified more than `maxAge`
    /// ago. Call once per app launch.
    static func evictExpiredFiles(maxAge: TimeInterval = maxAge, now: Date = Date()) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: MediaStorage.directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = now.addingTimeInterval(-maxAge)
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff
            else { continue }
            try? fileManager.removeItem(at: file)
        }
    }
}
