import Combine
import FirebaseFirestore
import Foundation

@MainActor
final class ConversationsService: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening(uid: String) {
        listener?.remove()
        listener = db.collection("conversations")
            .whereField("participants", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.conversations = snapshot.documents.compactMap { try? $0.data(as: Conversation.self) }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    deinit {
        listener?.remove()
    }
}
