import Combine
import FirebaseFirestore
import Foundation

/// Live listener (one per conversation) on each conversation's latest
/// message, for the chat list row preview/timestamp. Started from each
/// row's `onAppear` — safe to call repeatedly, a no-op once a listener for
/// that conversation is already running. Kept alive for the app session
/// rather than torn down on row disappearance: a personal chat app's
/// conversation count is small enough that this is negligible overhead,
/// and it's what makes the preview update live while the user is sitting
/// on the chat list, not just when the row first appears.
@MainActor
final class LastMessageDirectory: ObservableObject {
    @Published private(set) var lastMessageByConversation: [String: Message] = [:]

    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]

    func startListening(conversationId: String) {
        guard listeners[conversationId] == nil else { return }
        listeners[conversationId] = db.collection("conversations").document(conversationId)
            .collection("messages")
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self,
                      let message = snapshot?.documents.first.flatMap({ try? $0.data(as: Message.self) })
                else { return }
                self.lastMessageByConversation[conversationId] = message
            }
    }

    func preview(for conversationId: String) -> String? {
        guard let message = lastMessageByConversation[conversationId] else { return nil }
        if message.deletedForEveryone {
            return "This message was deleted"
        }
        switch message.type {
        case .text: return message.decryptedText(conversationId: conversationId)
        case .image: return "📷 Photo"
        case .gif: return "GIF"
        }
    }

    func timestamp(for conversationId: String) -> Date? {
        lastMessageByConversation[conversationId]?.createdAt
    }

    deinit {
        for listener in listeners.values {
            listener.remove()
        }
    }
}
