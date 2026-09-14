import FirebaseFirestore

/// Mirrors a `conversations/{id}` Firestore document. Conversations are
/// created out-of-band by an admin (Phase 3 task list), never by the client.
struct Conversation: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var participants: [String]

    func otherParticipant(myUid: String) -> String? {
        participants.first { $0 != myUid }
    }
}
