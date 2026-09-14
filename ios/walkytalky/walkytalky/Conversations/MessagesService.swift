import Combine
import FirebaseFirestore
import FirebaseStorage
import Foundation

@MainActor
final class MessagesService: ObservableObject {
    @Published private(set) var messages: [Message] = []
    /// Set when the listener itself fails (e.g. a Firestore rules rejection)
    /// — previously this was silently swallowed, so messages would just
    /// never appear with no visible reason why.
    @Published private(set) var listenErrorMessage: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening(conversationId: String) {
        listener?.remove()
        listener = db.collection("conversations").document(conversationId)
            .collection("messages")
            .order(by: "createdAt")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.listenErrorMessage = error.localizedDescription
                    return
                }
                guard let snapshot else { return }
                self.listenErrorMessage = nil
                self.messages = snapshot.documents.compactMap { document in
                    do {
                        return try document.data(as: Message.self)
                    } catch {
                        // A single malformed doc used to just vanish with no
                        // trace — log which one and why instead.
                        print("MessagesService: failed to decode message \(document.documentID): \(error)")
                        return nil
                    }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// Encrypts `text` with the conversation's current key before writing —
    /// throws `MessageEncryptionError.notPaired` if there isn't one yet.
    func sendText(conversationId: String, senderId: String, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let encrypted = try Message.encryptText(trimmed, conversationId: conversationId)
        let ref = db.collection("conversations").document(conversationId)
            .collection("messages").document()
        try await ref.setData([
            "senderId": senderId,
            "type": MessageType.text.rawValue,
            "text": encrypted.textBase64,
            "nonce": encrypted.nonceBase64,
            "keyVersion": encrypted.keyVersion,
            "createdAt": FieldValue.serverTimestamp(),
            "deletedFor": [],
            "deletedForEveryone": false,
            // Must be present (even as null), not just omitted: Message's
            // `@ServerTimestamp var deletedAt` throws DecodingError.keyNotFound
            // on a genuinely missing key, unlike a plain Optional.
            "deletedAt": NSNull(),
            "readBy": [],
        ])
    }

    /// "Delete for me": only ever adds the caller's own uid to `deletedFor`.
    /// Rendering filters out any message containing the viewer's own uid —
    /// see `ChatThreadView`.
    func deleteForMe(conversationId: String, messageId: String, uid: String) async throws {
        let ref = db.collection("conversations").document(conversationId)
            .collection("messages").document(messageId)
        try await ref.updateData([
            "deletedFor": FieldValue.arrayUnion([uid]),
        ])
    }

    /// Marks a message as read by the caller — only ever adds the caller's
    /// own uid to `readBy`. The sender never calls this for their own
    /// messages (`ChatThreadView` guards on that), and firestore.rules
    /// enforces it server-side too.
    func markRead(conversationId: String, messageId: String, uid: String) async throws {
        let ref = db.collection("conversations").document(conversationId)
            .collection("messages").document(messageId)
        try await ref.updateData([
            "readBy": FieldValue.arrayUnion([uid]),
        ])
    }

    /// "Delete for everyone" — sender-only, unrestricted by time. Clears the
    /// message content, tombstones it, and (for media) deletes the
    /// ciphertext blob from Storage.
    func deleteForEveryone(conversationId: String, message: Message) async throws {
        guard let messageId = message.id else { return }

        if message.type != .text, let storagePath = message.storagePath {
            try? await Storage.storage().reference(withPath: storagePath).delete()
        }

        let ref = db.collection("conversations").document(conversationId)
            .collection("messages").document(messageId)
        try await ref.updateData([
            "text": FieldValue.delete(),
            "storagePath": FieldValue.delete(),
            "nonce": FieldValue.delete(),
            "keyVersion": FieldValue.delete(),
            "deletedForEveryone": true,
            "deletedAt": FieldValue.serverTimestamp(),
        ])

        MediaStorage.delete(messageId: messageId)
    }

    deinit {
        listener?.remove()
    }
}
