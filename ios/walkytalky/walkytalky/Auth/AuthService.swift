import Combine
import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

enum AuthState: Equatable {
    case signedOut
    case checkingDevice
    case deviceConflict
    case signedIn(uid: String)
}

/// Handles Firebase anonymous sign-in and enforces that an account is only
/// ever active on a single device: on every sign-in this device's install ID
/// is written to `users/{uid}.activeDeviceId` inside a transaction, and the
/// transaction is rejected if a different device already holds that slot.
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var authState: AuthState = .signedOut
    @Published var lastErrorMessage: String?

    private let db = Firestore.firestore()
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    private let deviceIdAccount = "deviceInstallId"

    /// Stable per-install identifier, generated once and stored in the Keychain
    /// (not UserDefaults, so it survives app reinstall-and-restore edge cases
    /// as poorly as intended: a fresh Keychain item is only created if none exists).
    lazy var deviceId: String = {
        if let existing = KeychainService.loadString(account: deviceIdAccount) {
            return existing
        }
        let newId = UUID().uuidString
        KeychainService.saveString(newId, account: deviceIdAccount)
        return newId
    }()

    init() {
        // Safe to call from SwiftUI previews, which construct AuthService()
        // directly without going through walkytalkyApp.init().
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { await self.handleAuthChange(user: user) }
        }
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }

    private func handleAuthChange(user: User?) async {
        guard let user else {
            authState = .signedOut
            return
        }
        // Re-validate device ownership whenever we observe a signed-in user
        // (covers cold start with an existing session, not just fresh sign-in).
        // Firebase persists anonymous sessions locally across launches just
        // like regular accounts, so this is also what keeps someone signed
        // in without re-tapping "Continue" every launch.
        await claimDevice(uid: user.uid)
    }

    // MARK: - Sign in

    func signInAnonymously() async {
        do {
            _ = try await Auth.auth().signInAnonymously()
            // claimDevice runs via the auth state listener triggered above.
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Single-device enforcement

    private func claimDevice(uid: String) async {
        authState = .checkingDevice
        let userRef = db.collection("users").document(uid)
        let deviceId = self.deviceId

        do {
            _ = try await db.runTransaction { [weak self] transaction, errorPointer in
                guard let self else { return nil }
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(userRef)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }

                let existingDeviceId = snapshot.data()?["activeDeviceId"] as? String
                if let existingDeviceId, existingDeviceId != self.deviceId {
                    errorPointer?.pointee = NSError(
                        domain: "AuthService",
                        code: 409,
                        userInfo: [NSLocalizedDescriptionKey: "deviceConflict"]
                    )
                    return nil
                }

                transaction.setData([
                    "activeDeviceId": deviceId,
                    "updatedAt": FieldValue.serverTimestamp(),
                ], forDocument: userRef, merge: true)
                return nil
            }
            authState = .signedIn(uid: uid)
        } catch let error as NSError where error.code == 409 {
            authState = .deviceConflict
            try? Auth.auth().signOut()
        } catch {
            lastErrorMessage = error.localizedDescription
            authState = .signedOut
        }
    }

    // MARK: - Logout

    /// Signs out and releases this device's claim so the account can sign in
    /// elsewhere without hitting the single-device block. Note: for an
    /// anonymous account this permanently abandons it — there's no
    /// credential to sign back into the same uid later, so "sign out" here
    /// means "start over as a new anonymous identity" (standard behavior
    /// for Firebase anonymous auth, not specific to this app).
    func signOut() async {
        if let uid = Auth.auth().currentUser?.uid {
            try? await db.collection("users").document(uid).setData(
                ["activeDeviceId": FieldValue.delete()],
                merge: true
            )
        }
        try? Auth.auth().signOut()
        authState = .signedOut
    }

    /// Dismisses a device-conflict screen without touching the other device's session.
    func acknowledgeDeviceConflict() {
        authState = .signedOut
    }
}
