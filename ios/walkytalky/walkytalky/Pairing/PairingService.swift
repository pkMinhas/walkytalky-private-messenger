import CryptoKit
import Foundation

enum PairingService {
    /// Derives this conversation's AES-256-GCM key from our private key and
    /// the peer's public key (scanned from their QR code) via ECDH -> HKDF.
    /// The conversation ID is mixed in as the HKDF salt so the same two
    /// identity keys still produce distinct keys per conversation.
    static func deriveKey(peerPublicKeyData: Data, conversationId: String) throws -> SymmetricKey {
        let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)
        let sharedSecret = try CryptoIdentity.privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(conversationId.utf8),
            sharedInfo: Data("walkytalky-conversation-key".utf8),
            outputByteCount: 32
        )
    }
}
