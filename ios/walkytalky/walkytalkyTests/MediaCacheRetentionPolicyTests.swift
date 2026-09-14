//
//  MediaCacheRetentionPolicyTests.swift
//  walkytalkyTests
//

import Foundation
import Testing
@testable import walkytalky

@MainActor
struct MediaCacheRetentionPolicyTests {
    @Test func evictsOnlyFilesOlderThanMaxAge() throws {
        let oldId = "cache-old-\(UUID().uuidString)"
        let freshId = "cache-fresh-\(UUID().uuidString)"
        defer {
            MediaStorage.delete(messageId: oldId)
            MediaStorage.delete(messageId: freshId)
        }

        try MediaStorage.write(Data("old".utf8), messageId: oldId)
        try MediaStorage.write(Data("fresh".utf8), messageId: freshId)

        // Backdate the "old" file's modification date well past the cutoff.
        let oldDate = Date().addingTimeInterval(-1000)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: MediaStorage.fileURL(for: oldId).path
        )

        MediaCacheRetentionPolicy.evictExpiredFiles(maxAge: 500, now: Date())

        #expect(MediaStorage.exists(messageId: oldId) == false)
        #expect(MediaStorage.exists(messageId: freshId))
    }
}
