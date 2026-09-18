import Foundation

/// Per-conversation "No Face" mode: when on, every photo/GIF this device
/// sends in that conversation gets local face-detection + blur applied
/// before encryption (see `FaceBlurService`). Deliberately `UserDefaults`,
/// not Firestore — this is a purely local, per-device sending preference,
/// never synced. Turning it on doesn't tell the other participant, and
/// doesn't affect media they send to you.
enum NoFaceModeStore {
    private static func key(conversationId: String) -> String {
        "noFaceMode.\(conversationId)"
    }

    static func isEnabled(conversationId: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(conversationId: conversationId))
    }

    static func setEnabled(_ enabled: Bool, conversationId: String) {
        UserDefaults.standard.set(enabled, forKey: key(conversationId: conversationId))
    }
}
