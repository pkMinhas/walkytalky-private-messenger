import CryptoKit
import Foundation

/// This device's long-term X25519 identity keypair, generated once on first
/// launch and kept in the Keychain. Only the public key ever leaves the
/// device (embedded in the pairing QR code) — the private key is used
/// locally for ECDH during pairing and never transmitted.
enum CryptoIdentity {
    private static let privateKeyAccount = "x25519IdentityPrivateKey"

    static let privateKey: Curve25519.KeyAgreement.PrivateKey = {
        if let data = KeychainService.load(account: privateKeyAccount),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            return key
        }
        let newKey = Curve25519.KeyAgreement.PrivateKey()
        KeychainService.save(newKey.rawRepresentation, account: privateKeyAccount)
        return newKey
    }()

    static var publicKeyData: Data {
        privateKey.publicKey.rawRepresentation
    }
}
