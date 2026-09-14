//
//  TextEncryptionTests.swift
//  walkytalkyTests
//

import CryptoKit
import Foundation
import Testing
@testable import walkytalky

@MainActor
@Suite(.serialized)
struct TextEncryptionTests {
    private func cleanUp(conversationId: String, versions: ClosedRange<Int> = 1...3) {
        KeychainService.delete(account: "convKeyVersion_\(conversationId)")
        for v in versions {
            KeychainService.delete(account: "convKey_\(conversationId)_v\(v)")
        }
    }

    @Test func encryptThenDecryptRoundTripsThroughAMessage() throws {
        let conversationId = "text-enc-\(UUID().uuidString)"
        defer { cleanUp(conversationId: conversationId) }
        ConversationKeyStore.store(conversationId: conversationId, keyVersion: 1, key: SymmetricKey(size: .bits256))

        let encrypted = try Message.encryptText("hello walkytalky", conversationId: conversationId)
        let message = Message(
            senderId: "sender",
            type: .text,
            text: encrypted.textBase64,
            nonce: encrypted.nonceBase64,
            keyVersion: encrypted.keyVersion
        )

        #expect(message.decryptedText(conversationId: conversationId) == "hello walkytalky")
        // Ciphertext must not just be the plaintext re-encoded — confirm it's actually encrypted.
        #expect(message.text != "hello walkytalky")
    }

    @Test func encryptThrowsWhenNotPaired() {
        let conversationId = "text-enc-unpaired-\(UUID().uuidString)"
        #expect(throws: MessageEncryptionError.self) {
            try Message.encryptText("hello", conversationId: conversationId)
        }
    }

    @Test func decryptFallsBackToRawTextForLegacyUnencryptedMessages() {
        // A message sent before text encryption existed: no nonce/keyVersion.
        let message = Message(senderId: "sender", type: .text, text: "legacy plaintext")
        #expect(message.decryptedText(conversationId: "any-conversation") == "legacy plaintext")
    }

    @Test func decryptReturnsPlaceholderWhenKeyIsMissing() throws {
        let conversationId = "text-enc-missing-key-\(UUID().uuidString)"
        defer { cleanUp(conversationId: conversationId) }
        ConversationKeyStore.store(conversationId: conversationId, keyVersion: 1, key: SymmetricKey(size: .bits256))
        let encrypted = try Message.encryptText("secret", conversationId: conversationId)

        // Simulate a re-pair that discarded key version 1: message still
        // claims keyVersion 1, but that key no longer exists.
        ConversationKeyStore.store(conversationId: conversationId, keyVersion: 2, key: SymmetricKey(size: .bits256))

        let message = Message(
            senderId: "sender",
            type: .text,
            text: encrypted.textBase64,
            nonce: encrypted.nonceBase64,
            keyVersion: 1
        )
        #expect(message.decryptedText(conversationId: conversationId) == "🔒 Can't decrypt this message")
    }
}
