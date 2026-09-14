import Photos
import UIKit

/// Saves a decrypted image to the system Photo Library. Requests
/// `.addOnly` authorization lazily, on the first actual save attempt —
/// never upfront.
enum GallerySaver {
    enum SaveError: LocalizedError {
        case permissionDenied
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "Photos access was denied. Enable it in Settings to save images."
            case .underlying(let error): error.localizedDescription
            }
        }
    }

    static func save(_ image: UIImage) async throws {
        let status = await requestAddOnlyAuthorization()
        guard status == .authorized || status == .limited else {
            throw SaveError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaveError.underlying(error ?? NSError(domain: "GallerySaver", code: -1)))
                }
            }
        }
    }

    private static func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
