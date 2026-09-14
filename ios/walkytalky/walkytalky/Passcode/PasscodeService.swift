import Combine
import Foundation
import SwiftUI

/// Local passcode lock: set/verify a 6-digit passcode hashed with PBKDF2
/// (never stored or sent in plaintext, never written to Firestore), cold-start
/// and background-timeout locking, and an exponential lockout after failed
/// attempts. All state lives in the Keychain.
@MainActor
final class PasscodeService: ObservableObject {
    @Published private(set) var hasPasscode: Bool
    @Published private(set) var isLocked: Bool
    @Published private(set) var lockoutRemaining: TimeInterval = 0

    /// Background time before the app re-locks on foreground.
    /// TODO(HUMAN): confirm this value — task list default is 2 minutes.
    static let autoLockTimeout: TimeInterval = 120

    /// Lockout duration after the Nth consecutive failed attempt (index 0 = 1st failure).
    /// The last value repeats as a cap for further failures.
    /// TODO(HUMAN): confirm this curve — task list default is 5s, 30s, 2min, 10min, 30min cap.
    static let lockoutDelays: [TimeInterval] = [5, 30, 120, 600, 1800]

    private let hashAccount = "passcodeHash"
    private let saltAccount = "passcodeSalt"
    private let failedAttemptsAccount = "passcodeFailedAttempts"
    private let lockoutUntilAccount = "passcodeLockoutUntil"

    private var backgroundedAt: Date?
    private var lockoutTimer: Timer?

    init() {
        // Assign both from a local, not from each other: reading one
        // @Published property to set another here would touch `self`
        // (via ObservableObject's synthesized access) before every stored
        // property is initialized, which Swift rejects.
        let storedPasscodeExists = KeychainService.load(account: "passcodeHash") != nil
        hasPasscode = storedPasscodeExists
        isLocked = storedPasscodeExists
        refreshLockoutCountdown()
    }

    // MARK: - Setup / change

    func setPasscode(_ digits: String) {
        let salt = PBKDF2.randomSalt()
        let hash = PBKDF2.hash(password: digits, salt: salt)
        KeychainService.save(salt, account: saltAccount)
        KeychainService.save(hash, account: hashAccount)
        resetFailedAttempts()
        hasPasscode = true
        isLocked = false
    }

    // MARK: - Verification

    var isLockedOut: Bool { lockoutRemaining > 0 }

    @discardableResult
    func verify(_ digits: String) -> Bool {
        guard !isLockedOut,
              let salt = KeychainService.load(account: saltAccount),
              let storedHash = KeychainService.load(account: hashAccount)
        else { return false }

        let candidate = PBKDF2.hash(password: digits, salt: salt)
        let success = PBKDF2.constantTimeEquals(candidate, storedHash)
        if success {
            resetFailedAttempts()
            isLocked = false
        } else {
            registerFailedAttempt()
        }
        return success
    }

    private func registerFailedAttempt() {
        let attempts = failedAttempts + 1
        saveFailedAttempts(attempts)
        let delay = Self.lockoutDelays[min(attempts - 1, Self.lockoutDelays.count - 1)]
        saveLockoutUntil(Date().addingTimeInterval(delay))
        refreshLockoutCountdown()
    }

    private func resetFailedAttempts() {
        saveFailedAttempts(0)
        KeychainService.delete(account: lockoutUntilAccount)
        refreshLockoutCountdown()
    }

    private var failedAttempts: Int {
        guard let data = KeychainService.load(account: failedAttemptsAccount),
              let value = String(data: data, encoding: .utf8)
        else { return 0 }
        return Int(value) ?? 0
    }

    private func saveFailedAttempts(_ count: Int) {
        KeychainService.saveString(String(count), account: failedAttemptsAccount)
    }

    private func saveLockoutUntil(_ date: Date) {
        KeychainService.saveString(String(date.timeIntervalSince1970), account: lockoutUntilAccount)
    }

    private var lockoutUntil: Date? {
        guard let data = KeychainService.load(account: lockoutUntilAccount),
              let value = String(data: data, encoding: .utf8),
              let interval = TimeInterval(value)
        else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    /// Recomputes `lockoutRemaining` from Keychain state and (re)starts the
    /// once-a-second countdown timer while a lockout is active. Reading
    /// lockout state from the Keychain (rather than an in-memory value)
    /// means a lockout survives an app kill, per the task list's edge case.
    private func refreshLockoutCountdown() {
        lockoutTimer?.invalidate()
        lockoutTimer = nil

        guard let until = lockoutUntil else {
            lockoutRemaining = 0
            return
        }
        let remaining = until.timeIntervalSinceNow
        guard remaining > 0 else {
            lockoutRemaining = 0
            KeychainService.delete(account: lockoutUntilAccount)
            return
        }
        lockoutRemaining = remaining
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tickLockoutCountdown() }
        }
    }

    private func tickLockoutCountdown() {
        guard let until = lockoutUntil else {
            lockoutRemaining = 0
            lockoutTimer?.invalidate()
            lockoutTimer = nil
            return
        }
        let remaining = until.timeIntervalSinceNow
        if remaining <= 0 {
            lockoutRemaining = 0
            KeychainService.delete(account: lockoutUntilAccount)
            lockoutTimer?.invalidate()
            lockoutTimer = nil
        } else {
            lockoutRemaining = remaining
        }
    }

    // MARK: - Locking

    func lock() {
        guard hasPasscode else { return }
        isLocked = true
    }

    /// Call on every scene-phase change so backgrounding starts the auto-lock
    /// clock and returning to foreground re-locks if the timeout elapsed.
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = Date()
        case .active:
            if let backgroundedAt, Date().timeIntervalSince(backgroundedAt) >= Self.autoLockTimeout {
                lock()
            }
            self.backgroundedAt = nil
            refreshLockoutCountdown()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
