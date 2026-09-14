//
//  PairingTests.swift
//  walkytalkyTests
//

import CryptoKit
import Foundation
import Testing
@testable import walkytalky

struct PairingTests {
    @Test func payloadRoundTripsThroughQRString() {
        let payload = PairingPayload(conversationId: "conv123", publicKey: Data([1, 2, 3, 4]))
        let qrString = payload.qrString()
        #expect(qrString != nil)
        let decoded = PairingPayload.decode(qrString: qrString!)
        #expect(decoded?.conversationId == "conv123")
        #expect(decoded?.publicKey == Data([1, 2, 3, 4]))
    }

    @Test func decodeRejectsGarbage() {
        #expect(PairingPayload.decode(qrString: "not json") == nil)
    }

    @Test func bothSidesOfAnECDHExchangeDeriveTheSameKey() throws {
        // Simulate two devices' identity keys directly (independent of the
        // Keychain-backed CryptoIdentity singleton) to check the ECDH -> HKDF
        // math itself is symmetric.
        let alicePrivate = Curve25519.KeyAgreement.PrivateKey()
        let bobPrivate = Curve25519.KeyAgreement.PrivateKey()

        let aliceSecret = try alicePrivate.sharedSecretFromKeyAgreement(with: bobPrivate.publicKey)
        let bobSecret = try bobPrivate.sharedSecretFromKeyAgreement(with: alicePrivate.publicKey)

        let salt = Data("conv123".utf8)
        let info = Data("walkytalky-conversation-key".utf8)
        let aliceKey = aliceSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: 32)
        let bobKey = bobSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: 32)

        #expect(aliceKey.withUnsafeBytes { Data($0) } == bobKey.withUnsafeBytes { Data($0) })
    }

    @Test func differentConversationIdsProduceDifferentKeysForTheSamePeerPair() throws {
        let alicePrivate = Curve25519.KeyAgreement.PrivateKey()
        let bobPublic = Curve25519.KeyAgreement.PrivateKey().publicKey
        let secret = try alicePrivate.sharedSecretFromKeyAgreement(with: bobPublic)

        let info = Data("walkytalky-conversation-key".utf8)
        let keyA = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("convA".utf8), sharedInfo: info, outputByteCount: 32)
        let keyB = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("convB".utf8), sharedInfo: info, outputByteCount: 32)

        #expect(keyA.withUnsafeBytes { Data($0) } != keyB.withUnsafeBytes { Data($0) })
    }
}

@MainActor
@Suite(.serialized)
struct ConversationKeyStoreTests {
    private func cleanUp(conversationId: String, versions: ClosedRange<Int> = 1...5) {
        KeychainService.delete(account: "convKeyVersion_\(conversationId)")
        for v in versions {
            KeychainService.delete(account: "convKey_\(conversationId)_v\(v)")
        }
    }

    @Test func storeThenRetrieveRoundTrips() {
        let conversationId = "test-store-\(UUID().uuidString)"
        defer { cleanUp(conversationId: conversationId) }

        let key = SymmetricKey(size: .bits256)
        ConversationKeyStore.store(conversationId: conversationId, keyVersion: 1, key: key)

        #expect(ConversationKeyStore.currentVersion(conversationId: conversationId) == 1)
        let loaded = ConversationKeyStore.currentKey(conversationId: conversationId)
        #expect(loaded != nil)
        #expect(loaded!.withUnsafeBytes { Data($0) } == key.withUnsafeBytes { Data($0) })
    }

    @Test func rePairDiscardsThePreviousVersionsKeyMaterial() {
        let conversationId = "test-repair-\(UUID().uuidString)"
        defer { cleanUp(conversationId: conversationId) }

        let keyV1 = SymmetricKey(size: .bits256)
        ConversationKeyStore.store(conversationId: conversationId, keyVersion: 1, key: keyV1)
        #expect(ConversationKeyStore.key(conversationId: conversationId, keyVersion: 1) != nil)

        let keyV2 = SymmetricKey(size: .bits256)
        ConversationKeyStore.store(conversationId: conversationId, keyVersion: 2, key: keyV2)

        #expect(ConversationKeyStore.currentVersion(conversationId: conversationId) == 2)
        #expect(ConversationKeyStore.key(conversationId: conversationId, keyVersion: 1) == nil) // discarded
        #expect(ConversationKeyStore.key(conversationId: conversationId, keyVersion: 2) != nil)
    }
}
