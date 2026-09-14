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

    /// EXIF/GPS-strip -> encrypt -> upload to Storage -> write the Firestore
    /// message doc, in that order (stripping happens before any other
    /// processing, per the task list).
    func send(imageData: Data, type: MessageType, conversationId: String, senderId: String) async {
        state = .uploading(progress: 0)

        guard let stripped = ImageSanitizer.stripMetadata(from: imageData) else {
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
