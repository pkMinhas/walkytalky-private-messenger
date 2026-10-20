import Foundation

/// Each file in the encrypted disk cache is deleted once it's 24 hours old,
/// counted from when it was cached (downloaded, or uploaded by this
/// device). Anything still needed is re-downloaded the next time it's
/// viewed.
///
/// iOS gives the app no reliable way to run at an exact time, so the check
/// happens at launch and every time the app comes to the foreground; a file
/// that turns 24 hours old while the app isn't running is deleted at the
/// next of those. Decrypted copies need no handling here: `MediaMemoryCache`
/// is already empty at launch and is emptied whenever the app backgrounds.
enum MediaCachePurgePolicy {
    static let maxAge: TimeInterval = 24 * 60 * 60

    /// Pure decision, split out for tests. A modification date in the
    /// future means the clock was moved back; deleting then is the safe
    /// choice, since otherwise the file could outlive 24 hours by however
    /// far the clock moved.
    static func isExpired(cachedAt: Date, now: Date, maxAge: TimeInterval = maxAge) -> Bool {
        now < cachedAt || now.timeIntervalSince(cachedAt) >= maxAge
    }

    /// Deletes every cached file at least `maxAge` old, inside every
    /// conversation folder.
    static func purgeExpiredFiles(maxAge: TimeInterval = maxAge, now: Date = Date(), root: URL = MediaStorage.directory) {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for folder in folders where MediaStorage.isDirectory(folder) {
            guard let files = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in files {
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                      let cachedAt = values.contentModificationDate,
                      isExpired(cachedAt: cachedAt, now: now, maxAge: maxAge)
                else { continue }
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
