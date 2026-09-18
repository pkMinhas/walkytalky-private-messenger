import CryptoKit
import Foundation

/// PBKDF2-HMAC-SHA256, implemented on top of CryptoKit's `HMAC<SHA256>`
/// (CryptoKit has no PBKDF2 API of its own). Used to turn a 6-digit
/// passcode plus a per-device random salt into a Keychain-storable hash —
/// never the raw passcode.
///
/// `nonisolated`: pure, stateless computation with no UI-thread
/// requirement. `PasscodeService` (which calls this) runs it inside
/// `Task.detached` specifically so 100k HMAC iterations never block the
/// main actor — `nonisolated` alone doesn't move work off the main thread,
/// but it's required for a `Task.detached` closure to be able to call this
/// at all under the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
/// setting, which would otherwise pin this to the main actor by default.
nonisolated enum PBKDF2 {
    /// Cost tuned for a PIN that gets verified on every foreground/unlock:
    /// high enough to slow offline brute force of a leaked hash, low enough
    /// to feel instant (well under 100ms on any supported device).
    static let iterations = 100_000
    static let saltLength = 16
    static let keyLength = 32

    static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, saltLength, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
    }

    static func hash(password: String, salt: Data) -> Data {
        let key = SymmetricKey(data: Data(password.utf8))
        // keyLength == SHA256's 32-byte output, so a single PBKDF2 block suffices.
        var blockSalt = salt
        blockSalt.append(contentsOf: [0x00, 0x00, 0x00, 0x01]) // INT(1), big-endian

        var u = Data(HMAC<SHA256>.authenticationCode(for: blockSalt, using: key))
        var result = u
        if iterations > 1 {
            for _ in 1..<iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                for i in 0..<result.count {
                    result[i] ^= u[i]
                }
            }
        }
        return result
    }

    /// Constant-time comparison so a mismatched hash doesn't leak timing information.
    static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }
}
