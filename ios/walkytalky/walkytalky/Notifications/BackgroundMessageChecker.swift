import BackgroundTasks
import FirebaseAuth
import FirebaseFirestore
import Foundation
import UserNotifications

/// Occasional, best-effort background check for new messages, using
/// `BGTaskScheduler` + a local notification — deliberately not real push.
/// Push Notifications is one of the capabilities Apple gates behind a paid
/// Apple Developer Program membership; this project's whole self-hosting
/// pitch is that a free Apple ID is enough to build and run your own
/// instance, and real push would break that. `BGAppRefreshTask` and local
/// notifications both work on a free/personal-team provisioning profile.
///
/// The tradeoff, and it's a real one: iOS gives no guaranteed schedule for
/// this. It's opportunistic — timing depends on how often the app is
/// used, battery state, network conditions — and is cancelled outright if
/// the user force-quits the app from the app switcher. This is "better
/// than nothing," not a substitute for push.
///
/// Decryption is deliberately out of scope. The notification body is
/// always the fixed, generic "You have a new message" — this only ever
/// asks "does at least one new message exist since I last checked,"
/// never what it says, so nothing here needs a conversation's key.
enum BackgroundMessageChecker {
    static let taskIdentifier = "com.withpreet.walkytalky.refresh"

    private static let checkpointKey = "backgroundMessageChecker.checkpoint"
    /// What's requested of iOS as the next-check interval — purely a
    /// suggestion; the system decides the real timing.
    private static let requestedInterval: TimeInterval = 30 * 60

    /// Call once, as early as possible at launch — must happen before the
    /// app finishes launching for iOS to recognize the task at all.
    static func registerTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Queues the next opportunistic run. Called after handling the
    /// current run, and once the user is signed in with a live chat list
    /// on screen — no point scheduling checks before there's anything to
    /// check for.
    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: requestedInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().delegate = ForegroundNotificationPresenter.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// For diagnosing "no notification ever showed up": if this comes back
    /// anything other than `.authorized`, the user declined (or hasn't yet
    /// answered) the permission prompt, and no local notification —
    /// background-triggered or otherwise — will ever visibly appear,
    /// regardless of whether the rest of this pipeline is working.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    #if DEBUG
    /// Runs the exact same check-and-notify logic `handle(_:)` runs when
    /// iOS actually invokes the background task — callable directly, so
    /// the underlying query/notification logic can be verified without
    /// waiting on iOS's own opportunistic scheduling, which can genuinely
    /// take hours (or, in the Simulator, never happen at all without the
    /// `_simulateLaunchForTaskWithIdentifier:` LLDB command). Debug-only:
    /// this bypasses the "was it actually scheduled and did iOS actually
    /// run it" question entirely, which is deliberate for this purpose,
    /// but wrong to ship.
    static func debugTriggerNow() async -> Bool {
        let foundNew = await checkForNewMessages()
        if foundNew {
            postNotification()
        }
        return foundNew
    }
    #endif

    /// The user has just seen live, current data (the chat list is up and
    /// listening) — nothing before this moment should ever surface as a
    /// background notification, since it was either already seen or
    /// hadn't arrived yet. Resets the checkpoint a background check
    /// compares against.
    static func markSeenNow() {
        UserDefaults.standard.set(Date(), forKey: checkpointKey)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Always queue the next attempt before doing anything else — if
        // this run gets cut off by its expiration handler, there still
        // needs to be a future one queued.
        scheduleNextRefresh()

        let work = Task {
            let foundNew = await checkForNewMessages()
            if foundNew {
                postNotification()
            }
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
        }
    }

    /// One-shot query, not a live listener — a background task gets a
    /// short, fixed execution window, so this has to ask once and return,
    /// never stay running.
    private static func checkForNewMessages() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }

        let since = UserDefaults.standard.object(forKey: checkpointKey) as? Date ?? .distantPast
        let sinceTimestamp = Timestamp(date: since)
        let db = Firestore.firestore()
        defer { UserDefaults.standard.set(Date(), forKey: checkpointKey) }

        do {
            let conversations = try await db.collection("conversations")
                .whereField("participants", arrayContains: uid)
                .getDocuments()

            for conversation in conversations.documents {
                // Single-field range query only (no senderId filter here)
                // so this never needs a composite index a self-hoster
                // would have to know to deploy — "who sent it" is
                // filtered client-side below instead.
                let messages = try await db.collection("conversations")
                    .document(conversation.documentID)
                    .collection("messages")
                    .whereField("createdAt", isGreaterThan: sinceTimestamp)
                    .limit(to: 10)
                    .getDocuments()

                let hasMessageFromSomeoneElse = messages.documents.contains { doc in
                    (doc.data()["senderId"] as? String) != uid
                }
                if hasMessageFromSomeoneElse {
                    return true
                }
            }
        } catch {
            return false
        }

        return false
    }

    private static func postNotification() {
        let content = UNMutableNotificationContent()
        content.title = "walkytalky"
        content.body = "You have a new message"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Without a delegate, iOS silently drops a notification that fires while
/// the app is in the foreground — no banner, no sound, nothing — which is
/// almost certainly not what "the background check found something" should
/// do if it happens to run (or is debug-triggered) while the app is open.
private final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
