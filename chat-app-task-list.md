# Secure Chat iOS App — Task List

**Stack:** Swift/SwiftUI, Firebase (Auth, Firestore, Storage), CryptoKit, AVFoundation, PhotoKit
**Delivery:** TestFlight / Xcode installs only — no App Store public submission
**UI direction:** Visually similar to WhatsApp (chat list → thread view, message bubbles, bottom input bar with camera/gallery/send icons, top nav with contact name/avatar)

Tasks tagged `[HUMAN]` require a human to perform an account/console action, a physical two-device test, a design decision, or a manual review — Claude Code cannot complete these autonomously.

---

## Phase 0 — Project Setup

- [x] `[HUMAN]` Create/confirm Apple Developer account, bundle ID, provisioning profile — already done (Xcode project has `DEVELOPMENT_TEAM` and bundle ID `com.withpreet.walkytalky` set)
- [x] `[HUMAN]` Create Firebase project in Firebase console — already done (project `walkytalky-12c9a` exists per `GoogleService-Info.plist`)
- [x] `[HUMAN]` Create Xcode project (SwiftUI, iOS target) — already done
- [x] `[HUMAN]`Add Firebase iOS SDK via Swift Package Manager (FirebaseAuth, FirebaseFirestore, FirebaseStorage) — already done, resolved to 12.19.1
- [x] `[HUMAN]` Download and add `GoogleService-Info.plist` to project — already done
- [x] iOS app is in folder `./ios/walkytalky`
- [x] Firebase related code must be placed under `./firebase` — added `firebase.json`, `.firebaserc` (project `walkytalky-12c9a`), and moved rules under `firebase/SecurityRules/`
- [x] Set up project folder structure: `Auth/`, `Passcode/`, `Conversations/`, `Pairing/`, `Media/`, `Models/`, `SecurityRules/`

> **2026-09-14 pivot — magic-link auth replaced with anonymous auth.** Email-link sign-in turned out to be blocked in practice: Firebase Dynamic Links (the bridge that used to open a tapped email link directly in the app) was shut down, and the fallback of just opening the hosted action page in Safari couldn't hand control back to a native app without Universal Links, which in turn need a paid Apple Developer account and a real device to verify. Rather than keep fighting that chain, the user asked to drop magic-link auth entirely in favor of `Auth.auth().signInAnonymously()`. See the Phase 1 update below for what changed. The old "Configure URL scheme / associated domain for magic link deep link return" task, and the `[HUMAN]` "Enable Email Link sign-in" task that used to sit here, are both **removed** — no longer applicable.

---

## Phase 1 — Auth & Single-Device Enforcement

- [x] Build `SignInView` (email input field, "send magic link" button) — `ios/walkytalky/walkytalky/Auth/SignInView.swift`
- [x] Implement `AuthService.sendMagicLink(email:)` — `ios/walkytalky/walkytalky/Auth/AuthService.swift`
- [x] Handle incoming deep link, call `signInWithEmailLink` — `AuthService.handleIncomingURL(_:)`, wired via `.onOpenURL` in `walkytalkyApp.swift`
- [x] Generate persistent device install ID (`UUID`), store in Keychain — `AuthService.deviceId` via new `Models/KeychainService.swift`
- [x] On login: Firestore transaction to check/set `activeDeviceId` on `users/{uid}` — `AuthService.claimDevice(uid:email:)`
- [x] If `activeDeviceId` mismatch → block login, show "already signed in on another device" message — `Auth/DeviceConflictView.swift`
- [x] Implement session persistence (`AuthStateListener`) and logout flow — `AuthService.init()` listener + `AuthService.signOut()`
- [x] `[HUMAN]` Test single-device kickout manually with two physical/simulator devices — superseded, see below

**Verified so far (original, magic-link version):** `xcodebuild` succeeds (Debug, iOS Simulator), and the app installs/launches cleanly in the iOS 26.5 simulator showing `SignInView` with no crash. Caught and fixed a real ordering bug along the way: the `@StateObject authService = AuthService()` default-value initializer would have run before `walkytalkyApp.init()`'s `FirebaseApp.configure()` call, crashing at launch — fixed by explicitly assigning `_authService` inside `init()` after `configure()`.

### 2026-09-14 — Replaced magic-link auth with anonymous auth

At the user's request, removed magic-link sign-in entirely (see the Phase 0 pivot note above) and replaced it with `Auth.auth().signInAnonymously()`:

- `AuthService`: dropped `sendMagicLink`, `handleIncomingURL`, `cancelPendingEmailLink`, the `awaitingEmailLink` state, and the `email` field on the device-claim write; added `signInAnonymously()`. Single-device claim/kickout logic itself is untouched — same transaction, just without an email string attached.
- `SignInView`: replaced the email field + "check your email" flow with a single "Continue" button.
- `walkytalkyApp.swift`: removed the `.onOpenURL` deep-link handler (nothing to catch anymore).
- Removed now-dead magic-link-only config: the custom URL scheme in `Info.plist`, the Associated Domains entitlement + `walkytalky.entitlements` file, the `CODE_SIGN_ENTITLEMENTS` build setting, and the Firebase Hosting artifacts that existed solely to host the AASA file / authDomain page (`firebase/public/`, the `hosting` block in `firebase.json`). The actual deployed Hosting site (`walkytalky-12c9a.web.app`) is still live and harmless — left alone rather than torn down unprompted; disable it with `firebase hosting:disable` if you don't want it hanging around.
- `Models/AppUser.swift` deleted — dead code even before this change (nothing ever read it).
- `Conversations/ParticipantDirectory.swift` gutted: it existed only to resolve `users/{uid}.email` for chat-list/thread titles, and anonymous accounts have no email. It now just formats the uid (same public API, so `ChatListView`/`ChatThreadView` needed no changes). **Known UX consequence, not silently papered over:** conversation rows now show a truncated uid instead of anything human-readable, since there's no identity signal left at all. A nickname/profile feature would fix this but wasn't asked for.
- Single-device enforcement is now largely a defensive no-op in practice: an anonymous account is inherently tied to one device already (there's no credential to type in on a second device to reach the same uid), so the conflict path is very unlikely to trigger outside of someone deliberately copying Keychain/auth state across devices. Left the code as-is since it's still correct and harmless, just flagging that its original justification (prevent a shared *email* account from being used on two devices at once) no longer quite applies.
- Added `walkytalkyUITests/AnonymousSignInUITests.swift` — an actual tap-through UI test (`XCUIApplication`, taps "Continue", waits for "Create a passcode" to confirm sign-in completed). This is new: everything before this was build success + unit tests + static screenshots, never an automated real tap. Running it is what caught the bug below.

**Bug found and fixed via that UI test — not a code bug, a deployment gap:** the tap-through test failed with "Missing or insufficient permissions" on the `users/{uid}` write. `firebase/SecurityRules/firestore.rules` had been rewritten correctly back in Phase 1/3/8 and reviewed each time, but as far as I can tell was never actually deployed to the live project — whatever was live before didn't match the repo. Redeployed via `firebase deploy --only firestore:rules` (user approved), reran the test, and it passed clean on a freshly erased simulator: tap Continue → anonymous sign-in → device-claim transaction succeeds → lands on `PasscodeSetupView`. This is the first fully-automated, real-backend confirmation that the auth + single-device-claim path actually works end-to-end.

**Update:** `firebase/SecurityRules/storage.rules` (Phase 9) was in the same boat — deployed via `firebase deploy --only storage` (user approved), compiled clean. Both Firestore and Storage rules are now live and match the repo.

---

## Phase 2 — Local Passcode Lock

- [x] Build `PasscodeSetupView` (6-digit entry, shown after first sign-in) — `ios/walkytalky/walkytalky/Passcode/PasscodeSetupView.swift`, two-step enter/confirm, wired into `ContentView` when signed in with no passcode set yet
- [x] Implement passcode hashing (PBKDF2 or Argon2, per-device salt) via CryptoKit — `Passcode/PBKDF2.swift`; CryptoKit has no PBKDF2 API of its own, so PBKDF2-HMAC-SHA256 is built on `HMAC<SHA256>`, 100,000 iterations, 16-byte random salt per passcode
- [x] Store passcode hash + salt in Keychain (never Firestore) — via `Models/KeychainService.swift`, separate `passcodeHash`/`passcodeSalt` accounts
- [x] Build `PasscodeLockView` shown on cold start and after background timeout — `Passcode/PasscodeLockView.swift`
- [x] Define and implement background auto-lock timeout (e.g., 2 min) — **superseded 2026-09-14**: at the user's explicit request, minimizing the app now locks immediately, no grace period — see the dated note in this phase's section. The original `autoLockTimeout = 120s` placeholder (flagged `TODO(HUMAN)` since it was never confirmed) is gone; this answers that open question by replacing it entirely.
- [x] Build `ChangePasscodeView` (verify current → set new 6-digit) — `Passcode/ChangePasscodeView.swift`, reachable via a "Change Passcode" button on the signed-in placeholder screen; reuses `PasscodeService.verify` so a wrong current-passcode guess here still counts toward the same lockout
- [x] Implement exponential lockout:
  - [x] Failed-attempt counter in Keychain — `passcodeFailedAttempts` account
  - [x] Delay curve (e.g., 5s, 30s, 2min, 10min, 30min cap) — `PasscodeService.lockoutDelays` uses exactly that curve (task list default) — `[HUMAN]` confirm this is the right curve (marked `TODO(HUMAN)` in code)
  - [x] Countdown UI during lockout — `PasscodeLockView` shows "Try again in Xs/M:SS", input disabled while locked out
  - [x] Reset counter on successful unlock — `PasscodeService.resetFailedAttempts()`, called from `verify()` on success
- [ ] `[HUMAN]` Manual QA pass on lockout timing and edge cases (app kill during lockout, etc.)

**Verified so far:** `xcodebuild` build succeeds cleanly (no errors/warnings). Added `walkytalkyTests/PasscodeTests.swift` (9 Swift Testing cases) covering PBKDF2 correctness (deterministic, salt/password sensitivity, constant-time compare) and `PasscodeService` behavior (set/verify roundtrip, wrong-passcode lockout, lockout blocks further guesses without extending itself, successful unlock resets the delay curve) — all pass. Note: `PasscodeService` reads/writes fixed Keychain account names, so its tests are marked `@Suite(.serialized)`; running them with Swift Testing's default parallelism races on shared Keychain state and is expected to be flaky.

Caught and fixed a real init-order bug: reading the just-assigned `hasPasscode` to set `isLocked` inside `PasscodeService.init()` failed to compile (`@Published`'s `ObservableObject` machinery touches `self` before all stored properties are initialized) — fixed by computing both from a local `let` first. Also fixed a Swift-6-mode concurrency warning in the lockout countdown timer.

Not yet exercised end-to-end: the actual on-device UI flow (setup → background → re-lock → unlock, lockout countdown ticking down in the running app), since reaching it requires a signed-in session, which is still blocked on the Phase 0/1 `[HUMAN]` Firebase Auth console item. The Manual QA task above should cover this once that's unblocked.

### 2026-09-14 — Changed: lock immediately on minimize, not after a timeout

At the user's explicit request: minimizing the app now locks the UI immediately, replacing the 2-minute-grace-period design entirely (that value was always a `TODO(HUMAN)` placeholder, never confirmed — this instruction answers that open question).

`PasscodeService.handleScenePhaseChange` now calls `lock()` directly on `.background` (true minimize/app-switch, not the transient `.inactive` state a system alert or Control Center swipe briefly triggers) instead of recording a timestamp to check against a timeout on next foreground. Removed the now-dead `autoLockTimeout` constant and `backgroundedAt` tracking entirely, rather than leaving unused code behind.

Added 3 tests: backgrounding locks instantly with a passcode set (no elapsed-time dependency), is a no-op before any passcode exists (nothing to lock), and returning to `.active` doesn't itself unlock — still requires `verify()` to succeed. Full suite green (34/34).

---

## Phase 3 — Conversation & Message Plumbing

- [x] Define Firestore schema: `conversations/{id}` with `participants: [uidA, uidB]` — `ios/walkytalky/walkytalky/Models/Conversation.swift`
- [x] Define `messages` subcollection schema: `{senderId, type, text?, storagePath?, nonce?, keyVersion?, createdAt, deletedFor: [uid], deletedForEveryone: bool}` — `Models/Message.swift`; `storagePath`/`nonce`/`keyVersion` sit unused until Phase 5/6 wire up media
- [ ] `[HUMAN]` Admin manually creates `conversations/{id}` docs per user pair in Firebase console (out of app scope) — **nothing to test `ChatListView`/`ChatThreadView` against yet**
- [x] Build `ChatListView` — query conversations where `auth.uid in participants` — `Conversations/ChatListView.swift` (`ConversationsService` listener on `whereField("participants", arrayContains: uid)`); rows show the other participant's email (one-time `users/{uid}` lookup via new `Conversations/ParticipantDirectory.swift`) since the schema has no display-name field yet — full avatar/name/preview/unread styling is Phase 10
- [x] Build `ChatThreadView` — real-time Firestore listener on `messages`, WhatsApp-style bubble layout — `Conversations/ChatThreadView.swift` (`MessagesService` listener ordered by `createdAt`); sent/received bubble coloring and alignment done now, tail styling/date separators deferred to Phase 10
- [x] Implement plaintext text message send/receive — `MessagesService.sendText(conversationId:senderId:text:)`, wired to the composer's send button
- [x] Write Firestore security rules: conversations/messages readable/writable only if `auth.uid in participants` — rewrote `firebase/SecurityRules/firestore.rules` (was still the default 30-day-open template): `users/{uid}` locked to its own owner (needed for Phase 1's device-claim writes), `conversations` read-only to participants (writes are console-only per the task above), `messages` readable/creatable by participants (create requires `senderId == auth.uid`), update left open to participants for Phase 8's "delete for me", tightened further there for `deletedForEveryone`
- [x] `[HUMAN]` Review and approve security rules before deploying — approved and deployed 2026-09-14 (`firebase deploy --only firestore:rules`); compiled clean. Couldn't syntax-check via the Firestore emulator in this environment (no Java), but the real deploy compiling successfully covers that.

**Verified so far:** `xcodebuild` build succeeds cleanly, full test suite (Phase 2's 9 cases) still green — no regressions. App still installs/launches in the simulator with no crash. Could not exercise `ChatListView`/`ChatThreadView` against real data: that needs a signed-in session (blocked on the Phase 0/1 Firebase console item) *and* an admin-created conversation doc (the `[HUMAN]` task above), so the empty-state UI is the only path actually rendered so far.

### 2026-09-14 — Added: view your own uid, and admin-assignable display names

Two related additions at the user's request, on top of the anonymous-auth pivot (Phase 1 note above): since accounts are anonymous now, there's no name/email anywhere — a user needs a way to hand their uid to an admin, and once paired, some way to show a human-friendlier label than a raw uid.

- **"My User ID"** (`Conversations/MyUserIDView.swift`): shows the signed-in user's uid with copy-to-clipboard, reachable from `ChatListView`'s toolbar menu and, more usefully, directly from the empty "No conversations yet" state — exactly the moment someone needs to hand their uid to an admin. Verified end-to-end with a real tap-through UI test (`AnonymousSignInUITests.testViewMyUserIDFromEmptyChatList`): sign in, set a passcode, tap "View My User ID," confirm the uid renders and Copy works.
- **Admin-assignable display names**: an admin can set a short `displayId` per participant per conversation, at `conversations/{conversationId}/displaynames/{uid}` (doc shape `{ displayId: "AB" }`) — out-of-app, via the Firebase console, same convention as admin-created conversations. `ParticipantDirectory` looks it up and falls back to the uid's first+last character if none is set. Used everywhere a name is shown (`ChatListView` rows, `ChatThreadView` nav title) — no call sites needed new UI, just an added `conversationId` parameter on `resolve(_:in:)`.
  - Went through two rules iterations before landing here, both driven by the user's own review: first tried making the whole `users/{uid}` doc readable by any signed-in user (rejected — unnecessarily exposes `activeDeviceId` too); then a top-level `displaynames/{uid}` collection open to any signed-in user (rejected — can't be scoped to "only people who share a conversation with this uid," since Firestore rules can't scan collections to check conversation membership, only check a path they already know). Landed on nesting it under the conversation doc, which lets the existing participant-membership check apply directly, and matches the mental model that a display name is really a per-conversation label an admin sets, not a global profile field.
  - `firestore.rules` updated and deployed (user approved): `conversations/{conversationId}` now hosts shared `conversation()`/`isParticipant()` helper functions (hoisted up from `messages`, now also used by `displaynames`); the new `displaynames` subcollection is read-only to participants, no client write path.

**Verified:** full unit test suite green after each iteration (23/23), clean rules compile on each deploy, both UI tests still pass. Not yet exercised: an actual admin-set `displayId` rendering in the app (needs the `[HUMAN]` admin step of creating one in the console — same blocker as conversations themselves).

**2026-09-14 follow-up — real bug, caught by the user:** the data model and rules were already correctly scoped per-conversation, but `ParticipantDirectory`'s in-memory cache wasn't — it was keyed by uid alone (`displayIdsByUid: [String: String]`). Since an admin can set a *different* `displayId` for the same uid in different conversations (that's the whole point of nesting the doc under the conversation), the uid-only cache would resolve a name once for whichever conversation asked first, then silently reuse that same name for that uid everywhere else it appeared, ignoring the per-conversation scoping entirely. Fixed by keying the cache on `(conversationId, uid)` instead — `displayName(for:in:)` and `resolve(_:in:)` both now require the conversation id, not just the uid. Both call sites (`ChatListView` row title, `ChatThreadView` nav title) updated to pass `conversation.id`. Full suite still green (31/31) — this class of bug isn't unit-testable in isolation (same as `ConversationsService`/`MessagesService`/`LastMessageDirectory`, it's a live-Firestore-backed cache), verified by code review instead.

### 2026-09-14 — Text messages are now encrypted (user flagged this as a real gap)

Phase 3's original task explicitly said "plaintext text message send/receive," and that's what got built — only media (Phase 5/6) was ever scoped for AES-256-GCM encryption. The user correctly called this out as a real gap for a "secure chat" app once the pairing/key infrastructure existed to fix it, so text now goes through the same encryption path as media:

- `Models/Message.swift`: added `Message.encryptText(_:conversationId:)` (throws `MessageEncryptionError.notPaired` if there's no key yet) and `Message.decryptedText(conversationId:)`, both built on the existing `MediaCrypto`/`ConversationKeyStore` — no new crypto code, just reusing what Phase 4/5 already built. The `text` field's *meaning* changed: for `.text` messages it's now base64 ciphertext, with `nonce`/`keyVersion` populated exactly like media. **Backward compatible on purpose:** a message with no `nonce`/`keyVersion` (i.e., anything sent before this change) is rendered as literal stored plaintext rather than attempting to decrypt it — so no migration needed, nothing crashes on old data.
- `MessagesService.sendText` now encrypts before writing; `ChatThreadView`'s composer send button is gated on `isPaired` the same way the camera/gallery buttons already were (tapping while unpaired opens the pairing sheet instead of sending), and a send failure now surfaces as an alert instead of being silently swallowed. Updated the "not paired" banner copy from "for encrypted media" to "before messaging," since it's no longer just media.
- `MessageBubble` and `LastMessageDirectory`'s chat-list preview both call `decryptedText` now instead of reading `text` directly — the list preview was the one place this would've silently leaked raw ciphertext-as-text onto the screen if missed.
- Added `walkytalkyTests/TextEncryptionTests.swift` (4 cases): round-trip through an actual `Message`, throws when unpaired, legacy-plaintext fallback, and the "can't decrypt" placeholder when a message's `keyVersion` key has been discarded by a re-pair.

**Verified:** full suite green (27/27 unit tests). Re-ran both UI tests in isolation with a fresh simulator erase each time to confirm the `ChatThreadView` changes didn't regress sign-in/passcode/My-User-ID — both passed clean. (Running the two UI tests back-to-back in one invocation hit the same simulator/clone flakiness seen earlier this session — unrelated to this change; isolated runs are what's authoritative here.) Not yet exercised: an actual encrypted text message rendering end-to-end against real Firestore data, same blocker as everything else in this phase — needs an admin-created conversation first.

### 2026-09-14 — Real bug: messages weren't showing up at all (found via the user's first live test)

The user got an admin-created conversation working and hit this immediately: **no messages rendered, sent or received.** Console showed the actual cause: `DecodingError.keyNotFound` for `deletedAt`.

Root cause: `Message.deletedAt` is `@ServerTimestamp var deletedAt: Date?`. Unlike a plain `Optional`, Firebase's `@ServerTimestamp` wrapper does not tolerate the key being *entirely absent* from the Firestore document — it needs the key present, even as `null`. `deletedAt` is only ever written when a message gets deleted (Phase 8), so every ordinary message was missing that key outright, and `document.data(as: Message.self)` threw on every single one. Combined with `compactMap { try? ... }` silently dropping decode failures (see below), the result was every message vanishing with zero visible cause.

Two fixes:
- `MessagesService.sendText` and `MediaUploadService.send` now both write `"deletedAt": NSNull()` explicitly at message creation, so the key always exists from the start.
- Also fixed the silent-failure problem itself, independent of this specific bug: `MessagesService`'s snapshot listener used to discard its error entirely (`{ snapshot, _ in ... }`) and `compactMap { try? ... }` silently dropped any message that failed to decode. Now: listener errors publish to a new `listenErrorMessage` and render as a red banner in `ChatThreadView` (same treatment as the existing yellow "not paired" banner), and individual decode failures are logged to the console with the specific document ID and reason — this is exactly what surfaced the root cause above instead of leaving it a total mystery.

**Note for the user:** this fixes it for every message sent from now on. The one specific test message already in Firestore (`T3oWYm53JeqjJlIxPJ3r`) was written before this fix and is still missing the `deletedAt` key, so it'll keep failing to decode until either deleted or manually patched (add `deletedAt: null` to it in the Firebase console) — did not attempt to patch it myself, since that needs direct Firestore data access this environment doesn't have (see below).

**How this was diagnosed:** initially tried to inspect live Firestore data directly using the Firebase CLI's stored OAuth credentials (already used for the rules/hosting deploys this session) to read the actual document content — Claude Code's own sandbox correctly blocked reading that credential file as a likely exfiltration pattern, so backed off rather than working around it. Diagnosis instead came from code review plus the error-surfacing fix above, then the user pasting the actual console output, which named the exact field and exact error type.

**Verified:** full suite still green (27/27) after the fix.

---

## Phase 4 — Key Generation & Offline QR Pairing

- [x] Generate X25519 keypair on first launch via CryptoKit, private key → Keychain — `Pairing/CryptoIdentity.swift`
- [x] Build QR code generator (CoreImage) encoding `conversationId + publicKey` — `Pairing/QRCodeGenerator.swift` + `Pairing/PairingPayload.swift` (JSON payload, since `conversationId` and the public key both need to travel together)
- [x] Build QR scanner screen (AVFoundation) — `Pairing/QRScannerView.swift`
- [x] Implement ECDH (own private key + peer public key) → HKDF → AES-256-GCM key derivation — `Pairing/PairingService.swift`; conversation ID is mixed in as the HKDF salt so the same two people pairing in two different conversations still get distinct keys
- [x] Local key storage schema in Keychain: `{conversationId, keyVersion, key}` — `Pairing/ConversationKeyStore.swift`
- [x] Build `PairingView` UI flow: show my QR → scan peer's QR → confirm pairing success — `Pairing/PairingView.swift`
- [x] Implement re-pair flow: generates new `keyVersion`; old key discarded (old messages become undecryptable, per spec) — same `PairingView`, each run targets `currentVersion + 1` and `ConversationKeyStore.store` discards the previous version's key material
- [x] Add "not yet paired" state in `ChatThreadView` prompting user to pair before messaging — a dismissible banner + toolbar pairing icon; note: this gates **media** sending specifically (camera/gallery buttons prompt pairing first), not text — Phase 3's text messaging is explicitly plaintext/unencrypted per its own task, so there's no key to gate it on
- [ ] `[HUMAN]` Physical two-device pairing test (requires two real iOS devices in person — cannot be simulated)

**Verified so far:** `xcodebuild` build succeeds cleanly. Added `walkytalkyTests/PairingTests.swift` (6 cases): QR payload round-trip/garbage-rejection, ECDH+HKDF symmetry (both sides of a simulated exchange derive the identical key), conversation-ID domain separation, and `ConversationKeyStore` round-trip + re-pair key discarding. All pass (22/22 across the whole suite). Not exercised: the actual QR-camera-to-QR-camera flow, which needs two devices (the `[HUMAN]` task above) — also added `NSCameraUsageDescription` to `Info.plist` (default wording, not `[HUMAN]`-flagged in the task list but required for the scanner to not crash on first use; worth a quick wording check alongside the other Info.plist string).

---

## Phase 5 — Media Capture & Send Pipeline

- [x] Build camera capture flow (`PHPickerViewController` in camera mode or `UIImagePickerController`) → app-private temp storage, bypassing system camera roll — `Media/CameraCaptureView.swift` uses `UIImagePickerController`(`.camera`); captured image goes straight to encryption, never touches the camera roll
- [x] Build gallery picker flow (`PHPickerViewController`) for existing photos/GIFs — `Media/GalleryPickerView.swift`, detects GIF vs. static image via the item provider's type identifier
- [x] Implement EXIF/GPS stripping (ImageIO) applied to both capture and picker paths before any other processing — `Media/ImageSanitizer.swift`; decodes to `CGImage` first (pixel data only) rather than copying the source's metadata, which is what actually drops it
- [x] Implement AES-256-GCM encryption of stripped file using current conversation key + random nonce — `Media/MediaCrypto.swift`; nonce is kept as its own field (not CryptoKit's combined encoding) to match the schema's separate `nonce` column
- [x] Implement upload to Firebase Storage at `/media/{conversationId}/{messageId}` — `Media/MediaUploadService.swift`
- [x] Write Firestore message doc (`storagePath`, `nonce`, `keyVersion`, `senderId`, `type`, `createdAt`) — same file, written only after the upload succeeds
- [x] Build upload progress indicator + error/retry UI (WhatsApp-style upload spinner on bubble) — a progress bar + retry button in the composer area for now (functionally complete); moving this onto the bubble itself as an overlay is explicitly Phase 10's "media bubble styling" job

**Verified so far:** `xcodebuild` build succeeds cleanly. Added `walkytalkyTests/MediaTests.swift` (7 cases: encrypt/decrypt round trip, wrong-key rejection, tampered-ciphertext rejection, fresh-nonce-per-call, EXIF/GPS stripping, app-private storage round trip). Caught and fixed two real test bugs along the way (not product bugs): indexing a `Data` slice with literal `[0]` instead of `.startIndex` crashed the test process (`Data`'s subscript is absolute-index based), and the test renderer picked up the simulator's 3x screen scale instead of a fixed 1x. Not exercised: an actual upload against Firebase Storage — current `storage.rules` is still a deny-all placeholder (real rules are Phase 9's job), so uploads will fail with permission-denied until those are written and deployed, on top of still needing a signed-in + paired session.

### 2026-09-14 — Real bug: media sharing rejected with "User does not have permission"

First live media-sharing attempt (after text messages were confirmed working) failed with a Storage `unauthorized` error. Root cause: Phase 9's `storage.rules` relied on `firestore.get()` — a Storage Rules feature that reaches across into Firestore to check conversation participants, added recently enough that it's less battle-tested. It compiled cleanly on every deploy (both times), but wasn't actually evaluating to `true` for a real, valid participant.

Rather than keep guessing at that cross-service syntax and burning more live-test attempts, switched to a long-established, reliable Storage Rules pattern instead: participant uids now ride along as **custom metadata** on the Storage object itself, stamped on by `MediaUploadService.send` at upload time (`senderId`/`participant1`/`participant2`), and the rules check `resource.metadata` / `request.resource.metadata` directly — no cross-service call at all. `MediaUploadService.send` picked up a new `participants: [String]` parameter (threaded from `Conversation.participants`, already in scope in `ChatThreadView`). Also simplified the delete rule the same way — `senderId` for delete-for-everyone is now read from metadata rather than a second `firestore.get()` on the message doc.

`storage.rules` redeployed (user approved), compiled clean. Full unit suite still green (27/27).

### 2026-09-14 — Security review caught a real hole in that fix: self-declared metadata isn't authorization

The user asked me to evaluate an attack scenario on the metadata-based design above, and correctly identified a real vulnerability: `request.resource.metadata` is set by the uploading client itself — nothing forces `participant1`/`participant2` to match the real `conversations/{conversationId}.participants`. Any authenticated user (trivial to become one — this app uses anonymous auth) could self-declare themselves a participant of **any** `conversationId` and write into its media path.

**Actual blast radius, for the record:** bounded, not a full data breach. Firestore's own `messages` create rule *does* correctly verify real participant membership via a legitimate `get()`, so an attacker could pollute the Storage bucket under someone else's conversation path (storage-quota/cost abuse, unauthorized write access to a namespace) but could not get a fabricated message pointing at that object to actually appear in the victim's real message list — nothing in the app surfaces a Storage object except by first reading a legitimately-created Firestore message doc.

Given the choice between (a) retry the cross-service `firestore.get()` approach, (b) accept the bounded risk for now with a size cap, or (c) move authorization to a Cloud Function (needs Blaze plan), the user chose (a). Reverted the metadata-trust design:

- `storage.rules`: `isParticipant()` is back to the real `firestore.get(/databases/(default)/documents/conversations/$(conversationId)).data.participants` cross-service check for both `read` and `create`. Also added a check the first cross-service attempt didn't have: `create` now requires `request.resource.metadata.senderId == request.auth.uid`, binding the metadata's senderId to the actual authenticated caller — without this, senderId itself could be forged to someone else's uid. `delete` trusts `resource.metadata.senderId` for exactly this reason: it's now a rule-enforced invariant as of create time, not a client claim.
- `MediaUploadService.send` dropped the now-pointless `participants: [String]` parameter and the `participant1`/`participant2` metadata fields — authorization no longer depends on them, so keeping them would've just been dead weight. Metadata is now just `["senderId": senderId]`.
- Before redeploying, checked what I could about *why* the first cross-service attempt might have failed, since I couldn't rule out an infra-level cause (not just a syntax bug): confirmed via `firebase firestore:databases:list --json` that the database is Firestore Native mode, Standard edition, region `europe-west2` — nothing there points to an obvious incompatibility, though a regional/availability quirk for this specific Storage↔Firestore cross-service feature can't be fully ruled out without a live test.

`storage.rules` redeployed (user approved), compiled clean. Full unit suite still green (27/27). **Not yet verified against the real backend** — needs the user to try sharing media again. If this specific cross-service check fails again, that's meaningful evidence of a genuine reliability/availability issue with `firestore.get()` in this project (not a syntax mistake), at which point the fallback options are: accept the bounded metadata-only risk with a size cap, or move to a Cloud Function (Blaze plan).

### 2026-09-14 — Rules Playground gave "Null value error" — a real robustness gap, likely not the root cause

The user ran the new rules through the Firebase Console's Rules Playground simulator and got `Error running simulation — Error: simulator.rules line [17], column [31]. Null value error.` Column 31 on that line lands exactly at the start of `firestore.get(...)` — this is the standard symptom of chaining `.data` off a `get()` result for a document that doesn't exist: Firestore/Storage Rules throw on that rather than evaluating to a clean `false`. Most likely explanation: the Playground simulation was run against a `conversationId` that isn't a real Firestore document (easy to do — the simulator lets you type in an arbitrary test path), not a flaw in the real deployed rule for genuine app traffic.

Fixed the underlying robustness gap regardless, since a rule that throws instead of denying cleanly is bad practice independent of what triggered it here: added a `conversationExists()` guard (`firestore.exists(...)`) before the `firestore.get(...).data` access, so a nonexistent conversation now denies cleanly instead of erroring. Redeployed (user approved), compiled clean.

**Confirmed 2026-09-14: media sharing works end-to-end through the real app.** The cross-service `firestore.get()` check does work correctly for genuine traffic — the earlier failures traced back to (1) the metadata-trust design flaw, now fixed, and (2) the Console simulator's "Null value error" being a Playground-testing artifact, not a real bug. This closes out the whole media pipeline (Phases 5/6/9): capture/pick → strip EXIF → encrypt → upload → Firestore doc → decrypt → render, all verified against the live backend, with correctly-scoped security rules on both Firestore and Storage.

### 2026-09-14 — Real bug: some shared images came out rotated

Root cause: `ImageSanitizer.stripMetadata` decoded via `CGImageSourceCreateImageAtIndex`, which returns **raw, unrotated pixel data** — it never applies the EXIF orientation tag, that's purely a display-time hint for whoever reads the file next. Since stripping then discards all metadata (that's the whole point of the function), any photo relying on the tag rather than physically-rotated pixels — the norm for camera captures, since the sensor itself is landscape-oriented — came out permanently sideways once the tag was gone.

Fix: `ImageSanitizer.stripMetadata` now decodes through `UIImage(data:)` first (which *does* correctly read the EXIF orientation into `.imageOrientation`) and bakes that orientation into the pixel buffer via a redraw before handing off to the same strip-and-reencode path — so by the time metadata gets dropped, the pixels are already correctly oriented and don't need the tag anymore. No-op (just returns `.cgImage` directly) for already-upright images, so this doesn't add redraw overhead for the common case.

Added `ImageSanitizerTests.stripMetadataBakesInOrientationInsteadOfDroppingIt`, which constructs the exact failure scenario directly — an 8×4 image with unrotated pixels tagged EXIF orientation 6 ("rotate 90° CW") — and confirms the *old* code would have kept it 8×4 (tag dropped, still sideways) while the fix correctly produces 4×8 (rotation baked into the pixels). Full suite green (28/28).

### 2026-09-14 — Added: resize + reformat non-GIF images before upload

At the user's request: non-GIF images are now downscaled to fit a 3840px long edge (4K UHD's long edge — the common meaning of "4K" for a photo, which unlike video isn't fixed at 16:9; **flagging this specific number as a judgment call**, not stated anywhere in the task list) before encryption, aspect ratio preserved, never upscaling a smaller image. Also always re-encoded as JPEG at 95% quality regardless of the original format (HEIC, PNG, etc.).

`ImageSanitizer.prepareImageForUpload(_:)` does this in one redraw pass — decode, respect `imageOrientation` (reusing the same orientation-correctness fix from the entry above), scale to the target size, and JPEG-encode — rather than resizing and then separately re-stripping/re-encoding, which would have compounded lossy JPEG passes. `MediaUploadService.send` now branches on message type: `.image` goes through this new path, `.gif` keeps using the original `stripMetadata` (converting a GIF to JPEG would destroy the animation, and resizing wasn't asked for GIFs either).

Added 3 tests: downscale preserves aspect ratio (7680×3840 → 3840×1920), small images aren't upscaled, output is genuinely JPEG regardless of input container format. Full suite green (31/31).

---

## Phase 6 — Media Receive & Decrypt Pipeline

- [x] Listener for new media messages in active conversation — already covered by Phase 3's `MessagesService` listener (it listens to all message types, not just text)
- [x] Download ciphertext from Storage to app-private sandbox directory — `Media/MediaMessageView.swift`, written into `MediaStorage`
- [x] Look up matching `keyVersion` key from local Keychain store — via `ConversationKeyStore.key(conversationId:keyVersion:)`
- [x] Decrypt with AES-256-GCM — `MediaCrypto.decrypt`
- [x] Render decrypted image/GIF inline in chat bubble (from sandbox only — never system gallery) — wired into `ChatThreadView`'s `MessageBubble`; note: GIFs render as a static first frame (`UIImage(data:)` doesn't animate) — true animated playback isn't in the task list and would need a custom player, flagging as a known simplification rather than building it unasked
- [x] Handle missing-key case (message pre-dates a re-pair) → show "can't decrypt this message" placeholder bubble — same view, falls back to a lock-icon placeholder whenever the specific `keyVersion` key isn't in the Keychain

**Verified 2026-09-14:** confirmed working end-to-end against the real backend — user reports media sharing (which requires this download+decrypt+render path, not just the send side) works. See Phase 5's dated note for the full debugging story that got the security rules to this point.

---

## Phase 7 — Save to Gallery

- [x] ~~Add Save button/icon on received media bubbles~~ — **superseded 2026-09-14, see below**
- [x] ~~Request `Photos` write permission on first save attempt (not upfront)~~ — superseded
- [x] ~~`[HUMAN]` Add `NSPhotoLibraryAddUsageDescription` string to Info.plist~~ — superseded, key removed (nothing calls `PHPhotoLibrary` directly anymore)
- [x] ~~Write decrypted plaintext to system Photo Library via `PHPhotoLibrary`~~ — superseded
- [x] ~~Show success/failure feedback (checkmark/toast)~~ — superseded

**2026-09-14 — Consolidated into the fullscreen viewer's share sheet, at the user's request.** The original design put a standalone save button directly on each thumbnail (`Media/GallerySaver.swift`, explicit `PHPhotoLibrary` calls). Once the fullscreen image viewer (Phase 10) gained a proper Share button, that became redundant — the system share sheet's own "Save Image" action covers the exact same outcome. Removed the bubble-level save button and its `allowSave` plumbing from `MediaMessageView`/`ChatThreadView`, and deleted `GallerySaver.swift` entirely once it had zero remaining callers, along with the now-unused `NSPhotoLibraryAddUsageDescription` Info.plist key (the share sheet's save action is a system UI, not a `PHPhotoLibrary` call this app makes, so no privacy string is needed for it). Net effect: one save/share mechanism instead of two, and it now works for the viewer's own sent photos too, not just received ones (the old button was received-only per the original task wording; the share sheet has no such asymmetry). See Phase 10's update for the viewer changes themselves.

---

## Phase 8 — Delete Message (Self / Everyone)

- [x] Add long-press context menu on message bubbles (own and others') — WhatsApp-style action sheet — `.contextMenu` in `ChatThreadView`; "Delete for Me" always offered, "Delete for Everyone" only on own, non-tombstoned messages
- [x] Implement "Delete for me": add `auth.uid` to message's `deletedFor` array field; client filters out any message containing own uid from that array on render — `MessagesService.deleteForMe` (arrayUnion) + `ChatThreadView.visibleMessages` filter
- [x] Implement "Delete for everyone" (sender-only option):
  - [x] Update Firestore rule: only `senderId == auth.uid` may set `deletedForEveryone: true`
  - [x] On delete-for-everyone: clear `text`/`storagePath` content from doc, set `deletedForEveryone: true`, set `deletedAt` — also clears `nonce`/`keyVersion` (no reason to keep encryption metadata for content that's gone)
  - [x] If media message: also delete the ciphertext blob from Firebase Storage
  - [x] Render tombstoned message as "This message was deleted" bubble for both participants
- [x] "Delete for everyone" is unrestricted — no time limit; sender can delete at any point after sending — no time check anywhere in the code path
- [x] Update Firestore security rules to enforce delete permissions as above — `firebase/SecurityRules/firestore.rules`: the `messages` update rule now requires either a delete-for-me shape (only `deletedFor` touched, only adding the requester's own uid) or a delete-for-everyone shape (sender-only, `deletedForEveryone` set true)
- [x] `[HUMAN]` Review updated security rules before deploying — approved and deployed 2026-09-14 along with Phase 3's rules (same file)

**Verified so far:** `xcodebuild` build succeeds cleanly, full test suite still green (22/22, no regressions). Added `deletedAt` to the `Message` model (called for by this phase's own delete-for-everyone task but missing from Phase 3's original field list). Not exercisable end-to-end: needs the same real signed-in/paired/admin-created-conversation chain as Phases 3–7, plus deployed rules.

### 2026-09-14 — Added: read receipts

At the user's request: a double-checkmark indicator on the sender's own messages (gray = sent, blue = read), same convention as most chat apps.

- `Message`: new `readBy: [String]` field, same `arrayUnion`-based pattern as `deletedFor` — grows via `MessagesService.markRead`, which only ever adds the caller's own uid.
- `ChatThreadView`: each message bubble's `onAppear` calls `markReadIfNeeded`, which is a no-op unless the message (a) isn't the viewer's own, (b) isn't already marked read by them, and (c) isn't tombstoned. Since the message list uses `LazyVStack`, this naturally only fires as a bubble actually scrolls into view — a message below the fold hasn't been "read" yet, which is the right semantics.
- `MessageBubble` gained an `isReadByOther` parameter (computed in `ChatThreadView` from `message.readBy.contains(otherUid)`) and renders the checkmark pair next to the timestamp, only when `isMine` — applies to both text and media messages.
- `firestore.rules`: new `isMarkingRead()` alongside the existing `isDeleteForMe`/`isDeleteForEveryone` — the update may only ever touch `readBy`, only adding the caller's own uid, and explicitly **not** the sender marking their own message (enforced server-side, not just client-side).

Full suite still green (31/31). `firestore.rules` deployed 2026-09-14 (user approved), compiled clean.

---

## Phase 9 — Storage Security Rules

- [x] Write Storage rules mirroring Firestore participant check for `/media/{conversationId}/...` paths — `firebase/SecurityRules/storage.rules` (was still the deny-all placeholder from Phase 0); uses `firestore.get()` cross-service reads against the `conversations` doc, since Storage objects don't carry participant info themselves
- [x] Write Storage rule to allow ciphertext blob deletion only by original sender (supports delete-for-everyone) — checks `senderId` on the Firestore message doc, which by delete time always exists (upload happens before the message doc is written, so create-time can only check conversation membership — see comment in the rules file)
- [ ] Test rules using Firebase emulator / rules unit tests — **could not run**: the Firestore/Storage emulators are JVM-based and this environment has no Java installed
- [x] `[HUMAN]` Review and approve Storage rules before deploying to production project — approved and deployed 2026-09-14

---

## Phase 10 — WhatsApp-Style UI Pass

- [x] `[HUMAN]` Confirm color palette / branding direction (WhatsApp-like green accents, or neutral equivalent — avoid direct trademark copying) — set `AccentColor` to a muted teal-green (`#27988A` light / `#348AF3`→ dark variant, distinct from WhatsApp's specific green) as a placeholder default; please confirm or swap it
- [x] Chat list screen: avatar, name, last message preview, timestamp, unread indicator — `ChatListView`'s `ConversationRow` now shows all of these **except unread indicator**: the Phase 3 schema has no read-state field anywhere in the task list, and inventing one would mean adding backend schema not specified — flagging rather than guessing at a design
- [x] Chat thread screen: left/right message bubbles (sent vs. received), tail styling, timestamp per bubble, date separators — tail via `UnevenRoundedRectangle` (flattened corner on the sender's side), date separators computed by grouping messages by calendar day (`ThreadRow`/`DaySeparatorView` in `ChatThreadView.swift`)
- [x] Bottom input bar: text field, camera icon, gallery/attach icon, send button — already in place since Phase 5
- [x] Top nav bar: contact name, back button — `navigationTitle` + `NavigationStack`'s automatic back button (already in place since Phase 3)
- [x] Media bubble styling: rounded corners, upload/decrypt progress overlay, tap-to-fullscreen viewer — rounded corners + decrypt progress were already in `MediaMessageView` (Phase 6); added pinch-zoom tap-to-fullscreen viewer this phase. **Partial:** upload progress still lives in the composer bar (Phase 5), not as an overlay directly on an optimistic bubble — doing that properly needs a local pending-message model merged with the Firestore-sourced list, which felt like more surface area than this pass warranted; flagging instead of quietly shipping a half version
- [x] Long-press context menu styling for delete actions — using SwiftUI's native `.contextMenu` (added in Phase 8), which is the modern standard iOS long-press pattern; not rebuilt as a custom action sheet
- [ ] `[HUMAN]` Visual QA pass comparing against WhatsApp reference screens for spacing/feel

**Verified so far:** `xcodebuild` build succeeds cleanly, full test suite still green (22/22). App still launches without crashing in the simulator. Could not visually confirm the new accent color rendering in a live run (disabled-state buttons stay gray regardless of tint, and there's no way to type/tap through the simulator from this environment to reach an enabled state) — worth a glance next time the app is run interactively.

### 2026-09-14 — Real bug: chat list preview didn't update live

`LastMessageDirectory` (the chat-list row's last-message preview/timestamp) was a deliberate one-shot fetch on row `onAppear`, not a live listener — documented at the time as "close enough to live for a list the user reopens to see updates." The user correctly called this out as insufficient: it never updates while sitting on the chat list itself, only when a row re-appears (e.g. navigating back to it).

Fixed by making it a real live listener, one per conversation, started from the same `onAppear` call site (now `startListening` instead of `refresh`, safe to call repeatedly — a no-op once that conversation's listener exists) and kept alive for the app session rather than torn down per row. A personal chat app's conversation count is small enough that N small listeners is negligible overhead, and that's what makes the preview genuinely live.

Full suite still green (28/28). No Firebase deploy needed — purely a client-side listener-lifecycle change, no rules touched.

### 2026-09-14 — Fullscreen viewer: added pan and a share button, retired the bubble save button

At the user's request: `FullscreenImageViewer` now supports drag-to-pan while zoomed in (previously pinch-to-zoom only, no way to look around once zoomed past the frame), and a Share button next to the existing Close button, top of screen — `ShareLink` handing the decrypted `UIImage` to the system share sheet (AirDrop, Messages, Save Image, etc.).

Once that existed, the standalone save button on each thumbnail (Phase 7) became redundant, so per the user's explicit follow-up instruction it's gone — see Phase 7's entry above for the full removal (deleted `GallerySaver.swift`, the `allowSave` plumbing, and the now-unused `NSPhotoLibraryAddUsageDescription` Info.plist key).

Full suite still green (31/31). No Firebase deploy needed.

### 2026-09-17 — Media gallery: grid view + paged swipe viewer

At the user's request: a new toolbar button (grid icon, next to the pairing-status button) opens `MediaGalleryView`, a square-thumbnail `LazyVGrid` of every photo/GIF in the conversation. Tapping a thumbnail opens `MediaPagerView`, a `TabView` in `.page` style so the user can swipe left/right between every media item in the conversation, not just the one they tapped.

Refactored rather than duplicated: extracted the download-decrypt-cache pipeline out of `MediaMessageView.load()` into a shared `MediaDecryptor.decryptedImage(for:conversationId:)`, used by both the chat-bubble thumbnail and the new grid thumbnails/pager pages. Also extracted the pinch-zoom/pan gesture logic out of the formerly-private `FullscreenImageViewer` into a standalone `ZoomableImage`, and made `FullscreenImageViewer` itself non-private with an optional `pageInfo` label (e.g. "2 of 5") so the same zoom/pan/share chrome now serves both the single-image bubble viewer and each page of the gallery pager.

The grid/pager is populated from `messagesService.messages` (already live-loaded for the open thread) filtered to `.image`/`.gif` types, excluding anything deleted-for-everyone or deleted-for-me — no new Firestore query, no rules changes, no Firebase deploy needed.

Follow-up same day, per the user's request: tapping a media thumbnail directly in the chat thread (not just from the grid) now opens the same `MediaPagerView`, positioned at that message, instead of the old single-image `FullscreenImageViewer` — so swipe-to-prev/next works from both entry points. `ChatThreadView` now threads its `mediaMessages` list down through `MessageBubble` into `MediaMessageView`, which falls back to a single-item list if the message it's showing somehow isn't in that list (stale filter, edge case), so the viewer never ends up with zero pages.

Full suite still green (31/31) after both changes — no regressions in the extracted decrypt/crypto/cache logic.

### 2026-09-17 — Real bug: GIFs never animated, in the bubble or the pager

The user reported GIFs weren't animating anywhere. Two separate, compounding bugs:

1. **Upload-side (the real data loss):** `ImageSanitizer.stripMetadata(from:)` — the path GIFs go through instead of JPEG re-encoding — decoded via `UIImage(data:)` (which only ever surfaces a GIF's first frame) and wrote back exactly one `CGImageDestinationAddImage` call. Every GIF was silently flattened to a static single frame *before* it was ever encrypted and uploaded — this predates the media-gallery work above, so it's been broken since GIF support originally shipped, just never exercised with a real multi-frame GIF. Fixed by detecting a multi-frame source (`CGImageSourceGetCount(source) > 1`) and routing it through a new `stripMetadataFromAnimatedSource`, which copies every frame plus its own delay time and the source's loop count into the destination, instead of the single-frame path.
2. **Render-side:** even with animation preserved end-to-end, SwiftUI's `Image` never animates a multi-frame `UIImage` — it only ever shows one representative frame, full stop. Fixed by decoding GIFs into every individual frame + delay (new `GIFDecoder`, producing a `DecodedMedia` struct) and rendering through a new `MediaImageView`, which uses `TimelineView(.animation)` to cycle frames by elapsed time for an animated source and falls straight through to a plain `Image` for a static one (so no wasted redraws on the vastly more common case). `MediaDecryptor` now returns `DecodedMedia` instead of a bare `UIImage`; `MediaMessageView`, `MediaGridThumbnail`, `MediaPagerPage`, and `ZoomableImage`/`FullscreenImageViewer` all switched over — every place that shows decrypted media now animates GIFs consistently (chat bubble, grid, and paged viewer alike).

Added `GIFDecoderTests` (frame count, per-frame delay, the sub-0.02s-delay-clamps-to-0.1s convention real decoders use) and two `ImageSanitizerTests` regression cases (frame count and delay/loop-count survive `stripMetadata`) built on a shared real-GIF-container fixture helper. Full suite green (38/38). No Firebase deploy needed — purely client-side encode/decode/render.

### 2026-09-17 — Play/pause control on GIF thumbnails

At the user's request: an animated GIF's chat-bubble and grid thumbnails now show a small play/pause button overlaid in the corner (`MediaImageView`'s new `showsPlaybackControl` parameter, on for those two call sites, left off for the fullscreen pager since that wasn't asked for and already has its own zoom/pan/share chrome).

`TimelineView` has no built-in pause, so playback position is tracked as accumulated elapsed time plus an in-progress play session, frozen and resumed only from the button's own tap handler — deliberately never mutated from inside the `TimelineView` closure itself, which SwiftUI re-invokes far more often than is safe to write state from. Pausing freezes on whichever frame was showing; resuming continues from that same phase rather than jumping.

Full suite still green (38/38) — no new test added here since this is pure view-state/UI behavior with no non-trivial pure logic to isolate (the existing `GIFDecoderTests`/`ImageSanitizerTests` already cover the actual frame-timing math this button pauses and resumes). No Firebase deploy needed.

---

## Phase 11 — Hardening & QA

- [x] Decide and implement local decrypted-media cache retention policy (keep / evict after N days / re-decrypt on demand) — `[HUMAN]` confirm policy — went with "evict after N days, re-decrypt on demand" since `MediaMessageView` already re-downloads+re-decrypts whenever a cache file is missing (nothing is ever lost, just re-fetched); `Media/MediaCacheRetentionPolicy.swift`, default 30 days, run once per launch from `walkytalkyApp`. **Please confirm the 30-day window** — not specified anywhere in the task list, so this is a guess
- [ ] `[HUMAN]` End-to-end test: single-device kickout
- [ ] `[HUMAN]` End-to-end test: re-pairing and key-versioning (old messages undecryptable)
- [ ] `[HUMAN]` End-to-end test: passcode lockout timing/reset
- [ ] `[HUMAN]` End-to-end test: delete-for-self vs delete-for-everyone across both participants' devices
- [ ] `[HUMAN]` Manual security review: confirm no plaintext keys, passcodes, or decrypted media ever written to Firestore, Storage, or logs

**Verified so far:** `xcodebuild` build succeeds cleanly, full test suite green (23/23 — added `MediaCacheRetentionPolicyTests`, which backdates a cached file's modification time and confirms only the stale one gets evicted). Everything else in this phase is manual human QA against a real running app, which needs the whole chain (Firebase console setting, two physical devices, real pairing) that's been blocked throughout.

---

## Phase 12 — TestFlight Delivery

Every task in this phase is `[HUMAN]` — Apple Developer/App Store Connect account actions that Claude Code cannot perform. Nothing to build here.

- [ ] `[HUMAN]` Archive build in Xcode
- [ ] `[HUMAN]` Upload build to App Store Connect
- [ ] `[HUMAN]` Set up internal TestFlight testers group
- [ ] `[HUMAN]` Write TestFlight test instructions (flag that pairing requires two physical devices in person)
- [ ] `[HUMAN]` Collect and triage TestFlight feedback, iterate
