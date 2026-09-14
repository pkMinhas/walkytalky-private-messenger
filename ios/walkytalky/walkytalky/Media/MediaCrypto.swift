import CryptoKit
import Foundation

/// AES-256-GCM encrypt/decrypt for media blobs. The nonce is kept separate
/// from the uploaded ciphertext (rather than using CryptoKit's `combined`
/// encoding) so it can live in its own `nonce` field on the message doc,
/// matching the Phase 3 schema.
enum MediaCrypto {
    private static let tagLength = 16

    struct EncryptResult {
        let uploadData: Data // ciphertext + tag
        let nonceBase64: String
    }

    static func encrypt(_ plaintext: Data, key: SymmetricKey) throws -> EncryptResult {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        var uploadData = sealedBox.ciphertext
        uploadData.append(sealedBox.tag)
        return EncryptResult(uploadData: uploadData, nonceBase64: Data(nonce).base64EncodedString())
    }

    static func decrypt(_ uploadData: Data, nonceBase64: String, key: SymmetricKey) throws -> Data {
        guard let nonceData = Data(base64Encoded: nonceBase64) else {
            throw MediaCryptoError.invalidNonce
        }
        guard uploadData.count > tagLength else {
            throw MediaCryptoError.truncatedCiphertext
        }
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let ciphertext = uploadData.prefix(uploadData.count - tagLength)
        let tag = uploadData.suffix(tagLength)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    enum MediaCryptoError: LocalizedError {
        case invalidNonce
        case truncatedCiphertext

        var errorDescription: String? {
            switch self {
            case .invalidNonce: "Invalid encryption nonce."
            case .truncatedCiphertext: "Downloaded file is too short to be valid ciphertext."
            }
        }
    }
}
