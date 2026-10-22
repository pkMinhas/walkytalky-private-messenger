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
        let conversationId = "cache-conv-\(UUID().uuidString)"
        let oldId = "cache-old-\(UUID().uuidString)"
        let freshId = "cache-fresh-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: MediaStorage.conversationDirectory(conversationId))
        }

        try MediaStorage.write(Data("old".utf8), messageId: oldId, conversationId: conversationId)
        try MediaStorage.write(Data("fresh".utf8), messageId: freshId, conversationId: conversationId)

        // Backdate the "old" file's modification date well past the cutoff.
        let oldDate = Date().addingTimeInterval(-1000)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: MediaStorage.fileURL(for: oldId, conversationId: conversationId).path
        )

        MediaCacheRetentionPolicy.evictExpiredFiles(maxAge: 500, now: Date())

        #expect(MediaStorage.exists(messageId: oldId, conversationId: conversationId) == false)
        #expect(MediaStorage.exists(messageId: freshId, conversationId: conversationId))
    }
}
