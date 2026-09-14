import Combine
import FirebaseFirestore
import Foundation

/// Chat list/thread titles for the other participant. An admin can assign a
/// short `displayId` via a `conversations/{conversationId}/displaynames/{uid}`
/// doc — out-of-app, via the Firebase console, same convention as
/// admin-created conversations (Phase 3). Scoped under the conversation
/// (rather than a top-level collection) so security rules can restrict reads
/// to people who actually share a conversation with the uid being looked
/// up — see `firebase/SecurityRules/firestore.rules`. If no `displayId` is
/// set, falls back to the uid's first and last characters.
@MainActor
final class ParticipantDirectory: ObservableObject {
    @Published private(set) var displayIdsByUid: [String: String] = [:]

    private let db = Firestore.firestore()
    private var inFlight: Set<String> = []

    func displayName(for uid: String) -> String {
        displayIdsByUid[uid] ?? fallback(for: uid)
    }

    func resolve(_ uid: String, in conversationId: String) {
        guard displayIdsByUid[uid] == nil, !inFlight.contains(uid) else { return }
        inFlight.insert(uid)
        Task {
            defer { inFlight.remove(uid) }
            guard let snapshot = try? await db.collection("conversations").document(conversationId)
                .collection("displaynames").document(uid).getDocument(),
                  let displayId = snapshot.data()?["displayId"] as? String,
                  !displayId.isEmpty
            else { return }
            displayIdsByUid[uid] = displayId
        }
    }

    private func fallback(for uid: String) -> String {
        guard let first = uid.first, let last = uid.last else { return uid }
        return "\(first)\(last)"
    }
}
