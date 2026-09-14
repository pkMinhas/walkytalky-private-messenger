import Foundation

/// The JSON payload encoded into a pairing QR code: this device's identity
/// public key plus the conversation it's being offered for (so a scan
/// against the wrong conversation is rejected rather than silently paired).
struct PairingPayload: Codable {
    let conversationId: String
    let publicKey: Data

    func qrString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(qrString: String) -> PairingPayload? {
        guard let data = qrString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PairingPayload.self, from: data)
    }
}
