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
            // Metadata changes are needed to see the server confirm a list
            // that matches what was already cached: without them, that
            // confirmation is never delivered, so a removal that happened
            // while the app was closed would go unnoticed.
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.conversations = snapshot.documents.compactMap { try? $0.data(as: Conversation.self) }

                // Only a server-confirmed list is complete enough to act on.
                // A cached one may predate a conversation this user was just
                // added to, which would wipe media that's still valid. Every
                // returned doc counts, even one that fails to decode, since
                // the user is still a participant in it.
                guard !snapshot.metadata.isFromCache else { return }
                let activeIds = Set(snapshot.documents.map(\.documentID))
                Task.detached(priority: .utility) {
                    MediaStorage.deleteConversations(notIn: activeIds)
                }
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
