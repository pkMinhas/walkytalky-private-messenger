import Combine
import FirebaseFirestore
import FirebaseStorage
import Foundation

@MainActor
final class MediaUploadService: ObservableObject {
    enum UploadState: Equatable {
        case idle
        case uploading(progress: Double)
        case failed(String)
    }

    @Published private(set) var state: UploadState = .idle

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    /// No Face mode (blur) -> EXIF/GPS-strip (+ resize/reformat for non-GIF
    /// images) -> encrypt -> upload to Storage -> write the Firestore
    /// message doc, in that order (face-blur and metadata-stripping both
    /// happen before any other processing, and before encryption, so
    /// there's never a chance of an unblurred/un-stripped original leaving
    /// the device).
    func send(imageData: Data, type: MessageType, conversationId: String, senderId: String) async {
        state = .uploading(progress: 0)

        var sourceData = imageData
        if NoFaceModeStore.isEnabled(conversationId: conversationId) {
            do {
                // Face detection + blur is real (if brief) CPU/ML work —
                // detached so it never stalls the main actor this class is
                // pinned to. Fails closed: if blurring itself fails while
                // No Face mode is on, the send is aborted rather than
                // silently uploading an unprotected original.
                sourceData = try await Task.detached(priority: .userInitiated) {
                    try FaceBlurService.apply(to: imageData, type: type)
                }.value
            } catch {
                state = .failed("Couldn't blur faces for No Face mode, so this wasn't sent.")
                return
            }
        }

        // GIFs go through plain metadata-stripping only — converting one to
        // JPEG would destroy the animation. Static images additionally get
        // downscaled to fit 4K and normalized to JPEG @ 95%.
        let prepared = type == .image
            ? ImageSanitizer.prepareImageForUpload(sourceData)
            : ImageSanitizer.stripMetadata(from: sourceData)
        guard let stripped = prepared else {
            state = .failed("Couldn't process this image.")
            return
        }
        guard let key = ConversationKeyStore.currentKey(conversationId: conversationId),
              let keyVersion = ConversationKeyStore.currentVersion(conversationId: conversationId)
        else {
            state = .failed("Not paired with this contact yet.")
            return
        }

        let messageRef = db.collection("conversations").document(conversationId)
            .collection("messages").document()
        let messageId = messageRef.documentID

        do {
            let encrypted = try MediaCrypto.encrypt(stripped, key: key)
            let storagePath = "media/\(conversationId)/\(messageId)"
            let storageRef = storage.reference(withPath: storagePath)

            // storage.rules binds this to the authenticated caller's own uid
            // at create time (request.resource.metadata.senderId ==
            // request.auth.uid), so it can't be spoofed as someone else's —
            // that's what makes trusting resource.metadata.senderId safe
            // for the delete rule later.
            let metadata = StorageMetadata()
            metadata.customMetadata = ["senderId": senderId]

            try await uploadWithProgress(data: encrypted.uploadData, metadata: metadata, to: storageRef)

            try await messageRef.setData([
                "senderId": senderId,
                "type": type.rawValue,
                "storagePath": storagePath,
                "nonce": encrypted.nonceBase64,
                "keyVersion": keyVersion,
                "createdAt": FieldValue.serverTimestamp(),
                "deletedFor": [],
                "deletedForEveryone": false,
                // Must be present (even as null), not just omitted: Message's
                // `@ServerTimestamp var deletedAt` throws DecodingError.keyNotFound
                // on a genuinely missing key, unlike a plain Optional.
                "deletedAt": NSNull(),
                "readBy": [],
            ])
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func uploadWithProgress(data: Data, metadata: StorageMetadata, to ref: StorageReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let uploadTask = ref.putData(data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            uploadTask.observe(.progress) { [weak self] snapshot in
                guard let progress = snapshot.progress else { return }
                let fraction = Double(progress.completedUnitCount) / Double(max(progress.totalUnitCount, 1))
                Task { @MainActor in self?.state = .uploading(progress: fraction) }
            }
        }
    }
}
