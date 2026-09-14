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
    /// A display name is genuinely per-conversation, not a global identity
    /// for a uid — an admin can set a different displayId for the same
    /// person in different conversations, matching where the data actually
    /// lives. Caching by uid alone would let a name resolved in one
    /// conversation silently leak into another.
    private struct Key: Hashable {
        let conversationId: String
        let uid: String
    }

    @Published private var displayIdsByKey: [Key: String] = [:]

    private let db = Firestore.firestore()
    private var inFlight: Set<Key> = []

    func displayName(for uid: String, in conversationId: String) -> String {
        displayIdsByKey[Key(conversationId: conversationId, uid: uid)] ?? fallback(for: uid)
    }

    func resolve(_ uid: String, in conversationId: String) {
        let key = Key(conversationId: conversationId, uid: uid)
        guard displayIdsByKey[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        Task {
            defer { inFlight.remove(key) }
            guard let snapshot = try? await db.collection("conversations").document(conversationId)
                .collection("displaynames").document(uid).getDocument(),
                  let displayId = snapshot.data()?["displayId"] as? String,
                  !displayId.isEmpty
            else { return }
            displayIdsByKey[key] = displayId
        }
    }

    private func fallback(for uid: String) -> String {
        guard let first = uid.first, let last = uid.last else { return uid }
        return "\(first)\(last)"
    }
}
