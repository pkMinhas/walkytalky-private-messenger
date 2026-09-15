# walkytalky — Android Task List

**Goal:** an Android client with feature parity with the current iOS app, interoperating with the *same* Firebase backend — an Android user and an iOS user should be able to pair and chat with each other, not just with other Android users.

**Stack:** Kotlin, Jetpack Compose, Firebase Android SDK (Auth, Firestore, Storage), Android Keystore, CameraX, javax.crypto / Tink

Tasks tagged `[HUMAN]` require a human to perform an account/console action, a physical two-device test, a design decision, or a manual review — Claude Code cannot complete these autonomously.

This list assumes the iOS app (and its Firestore/Storage schema and security rules) already exists and is not being redesigned — Android is a new *client* against an existing *protocol*. Where iOS's own build history mattered (e.g. "text messages started out plaintext, then got encrypted later"), this list skips straight to building the *current* behavior — there's no reason to replicate iOS's incremental discovery process.

---

## Cross-platform correctness — read this before Phase 4 or 5

The single biggest risk in this whole effort is a subtly-wrong crypto implementation that produces working-looking but incompatible output — Android-to-Android chat would appear to work fine in testing while silently failing to interoperate with iOS. These are the exact byte-level contracts to match (see `README.md`'s "Wire protocol" section, and the iOS source under `ios/walkytalky/walkytalky/Pairing/` and `Media/MediaCrypto.swift` for the reference implementation):

- **QR payload**: JSON `{"conversationId": "<string>", "publicKey": "<base64, raw 32-byte X25519 public key>"}` — exact key names, exact encoding.
- **Key derivation**: `HKDF-SHA256(ECDH(myPrivateKey, peerPublicKey), salt: UTF-8(conversationId), info: UTF-8("walkytalky-conversation-key"), length: 32 bytes)` — the salt and info strings are literal and must match exactly, or the derived key will silently differ.
- **Encryption**: AES-256-GCM, random 12-byte nonce. Nonce stored separately (base64) in the Firestore `nonce` field. The stored/uploaded payload is `ciphertext || 16-byte GCM tag` concatenated — this is what `Cipher.getInstance("AES/GCM/NoPadding")` naturally produces from `doFinal()`, so a straightforward implementation should match, but confirm it explicitly rather than assuming.
- **Firestore message doc shape**: `senderId, type, text?, storagePath?, nonce?, keyVersion?, createdAt, deletedFor: [], deletedForEveryone: false, deletedAt: null, readBy: []`. Note `deletedAt` and `readBy` must be *present* at creation (even as null/empty), not omitted — iOS hit a real decode bug from this exact thing (a Firebase Swift property wrapper that throws on a missing key rather than defaulting), and while the Kotlin SDK's own data-class mapping may behave differently, write the field explicitly anyway so the schema stays consistent across clients regardless of either SDK's specific decode quirks.

**The acceptance test for Phase 4 that actually matters**: pair an Android device with a real iOS device (or simulator) via QR, and confirm a message sent from one decrypts correctly on the other. Do this before building anything on top of the crypto layer.

---

## Phase 0 — Project Setup

- [ ] `[HUMAN]` Register an Android app in the Firebase project (existing project if you want Android/iOS users to actually interoperate, or your own self-hosted project — see `README.md`), package name matching your chosen `applicationId`
- [ ] `[HUMAN]` Download `google-services.json`, add to the app module
- [ ] Create Android Studio project (Kotlin, Jetpack Compose, min SDK 26+ recommended, target latest)
- [ ] Add Firebase Android SDK via Gradle (BoM: `firebase-auth`, `firebase-firestore`, `firebase-storage`)
- [ ] Android app lives in `./android/walkytalky` (parallel to `./ios/walkytalky`)
- [ ] Set up module/package structure mirroring iOS: `auth/`, `passcode/`, `conversations/`, `pairing/`, `media/`, `models/`

---

## Phase 1 — Auth & Single-Device Enforcement

- [ ] `SignInScreen` (Compose): a single "Continue" action triggering `FirebaseAuth` anonymous sign-in — no email/password UI, matching iOS
- [ ] `AuthRepository.signInAnonymously()`
- [ ] Persistent device install ID: generate a UUID once, store via `EncryptedSharedPreferences` (Android Keystore-backed) — not plain `SharedPreferences`
- [ ] On login: Firestore transaction to check/set `activeDeviceId` on `users/{uid}` — identical schema/logic to iOS, no backend changes needed
- [ ] Device-conflict screen ("already signed in on another device")
- [ ] Session persistence via `FirebaseAuth`'s own auth-state listener + logout flow (clears `activeDeviceId` on sign-out, same as iOS)
- [ ] `[HUMAN]` Manual test: single-device kickout. Note (matches an iOS finding): since accounts are anonymous, this scenario is hard to trigger naturally — there's no credential to sign in with on a second device to reach the *same* uid, so this is mostly a defensive no-op in practice, not a commonly-hit path.

---

## Phase 2 — Local Passcode Lock

- [ ] `PasscodeSetupScreen` (Compose), 6-digit entry, shown after first sign-in
- [ ] PBKDF2-HMAC-SHA256 hashing via `javax.crypto` (`SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")`) — match iOS's 100,000 iterations and per-device random salt for consistency, though this doesn't need to be byte-identical across platforms (unlike the pairing crypto) since passcodes are purely local, never synced
- [ ] Store passcode hash + salt via Android Keystore-backed storage — never plain `SharedPreferences`, never Firestore
- [ ] `PasscodeLockScreen`: shown on cold start, and immediately when the app is backgrounded (Android's `ON_STOP` lifecycle event) — **no grace period**, matching iOS's current behavior (this was a deliberate iOS design change; don't build a timeout-based version)
- [ ] `ChangePasscodeScreen` (verify current → set new)
- [ ] Exponential lockout: failed-attempt counter + delay curve (5s / 30s / 2min / 10min / 30min cap, matching iOS) + countdown UI + reset on success — persist in the same Keystore-backed storage so a lockout survives a process kill
- [ ] `[HUMAN]` Manual QA pass on lockout timing and edge cases (app kill during lockout, etc.)

---

## Phase 3 — Conversation & Message Plumbing

No backend changes — this phase is purely client-side against the existing schema/rules.

- [ ] `ChatListScreen`: live query on `conversations` where `participants` array-contains the signed-in uid
- [ ] Chat list row: admin-assigned `displayId` (fall back to first+last character of the uid if none is set — matches iOS), live last-message preview + relative timestamp. **Use a live listener, not a one-shot fetch** — iOS shipped a one-shot version first and had to fix it because the preview didn't update while sitting on the chat list; build the listener version from the start.
- [ ] `ChatThreadScreen`: live listener on `messages` ordered by `createdAt`, WhatsApp-style bubbles (sent/received alignment and styling, date separators)
- [ ] Messages are encrypted from day one (see the cross-platform correctness section above and Phase 4/5) — there is no plaintext milestone to build toward
- [ ] "My User ID" screen with copy-to-clipboard, reachable from the toolbar and the empty chat-list state — mirrors iOS `MyUserIDView`, this is how a user hands their uid to an admin
- [ ] Admin-assignable display names: read from `conversations/{conversationId}/displaynames/{uid}`. **Cache scoped by `(conversationId, uid)`, not uid alone** — iOS shipped a uid-only cache first and had a real bug where a name resolved for one conversation silently leaked into another, since the same uid can have a different display name per conversation. Don't repeat that mistake.

---

## Phase 4 — Key Generation & Offline QR Pairing

See the cross-platform correctness section at the top of this file — this phase is where getting the byte-level details right actually matters.

- [ ] Generate an X25519 identity keypair on first launch, private key in Android Keystore (hardware-backed where available)
- [ ] QR code generation (e.g. ZXing) encoding the payload above
- [ ] QR scanning (CameraX + ML Kit barcode scanning, or ZXing) — no `android.permission.CAMERA`-triggering surprises; request permission only when the user opens the scanner, not upfront
- [ ] ECDH + HKDF key derivation exactly as specified above
- [ ] Local key storage keyed by `(conversationId, keyVersion)` — mirrors iOS's `ConversationKeyStore`
- [ ] `PairingScreen`: show my QR → scan peer's QR → confirm success
- [ ] Re-pair flow: generates a new `keyVersion`, discards the old key (old messages under that version become permanently undecryptable — this is the existing, intentional behavior, not something to "fix")
- [ ] "Not paired" state in the chat thread, gating message *sending* (not receiving/viewing — a paired peer's already-sent messages should still render)
- [ ] `[HUMAN]` Physical two-device pairing test — **ideally one Android device and one real iOS device**, to prove actual cross-platform interoperability, not just Android-to-Android

---

## Phase 5 — Media Capture & Send Pipeline

- [ ] Camera capture via CameraX, straight into app-private storage — never through `MediaStore`/the public gallery
- [ ] Gallery picker via the Android Photo Picker (`PickVisualMedia`) for existing photos/GIFs
- [ ] EXIF/GPS stripping via `androidx.exifinterface`, applied before any other processing, for both capture and picker paths
- [ ] For non-GIF images: downscale to a 3840px long edge (aspect ratio preserved, never upscaling), re-encode as JPEG @ 95% — matches iOS's current behavior (this wasn't in iOS's original spec either; it was added later at the maintainer's request, so build straight to it)
- [ ] GIFs: metadata-strip only, no resize/reformat, preserve the GIF format (converting to JPEG would destroy the animation) — matches iOS
- [ ] AES-256-GCM encryption using the current conversation key + random nonce, exact ciphertext layout as specified above
- [ ] Upload to Firebase Storage at `media/{conversationId}/{messageId}`, with `senderId` set as custom object metadata (`request.resource.metadata.senderId`) — **required by the already-deployed Storage rules**, which bind this at create time and trust it for delete-for-everyone later; the object won't be readable/writable without it matching the real authenticated uploader
- [ ] Write the Firestore message doc with the exact field shape from the cross-platform correctness section
- [ ] Upload progress indicator + error/retry UI

---

## Phase 6 — Media Receive & Decrypt Pipeline

- [ ] The live listener from Phase 3 already covers new media messages arriving — no separate listener needed
- [ ] Download ciphertext from Storage to app-private storage (not `MediaStore`)
- [ ] Look up the matching `keyVersion` key from local Keystore-backed storage
- [ ] Decrypt with AES-256-GCM — split the trailing 16 bytes off as the GCM tag, the rest is ciphertext, nonce comes from the Firestore `nonce` field
- [ ] Render the decrypted image inline in the chat bubble, from app-private storage only — never through `MediaStore`/the public gallery
- [ ] Missing-key case (message predates a re-pair): "can't decrypt this message" placeholder, not a crash

---

## Phase 7 — Share / Save

iOS does *not* have a dedicated save-to-gallery button — an earlier version did, but it was deliberately removed once the fullscreen viewer gained a Share button, since the system share sheet's own "Save Image" action covers the same outcome with less custom code. Build Android the same way from the start:

- [ ] Fullscreen image viewer: pinch-to-zoom, drag-to-pan while zoomed in, double-tap to toggle zoom
- [ ] Share button using `Intent.ACTION_SEND` — the system share sheet provides "Save to Photos"/Files-equivalent actions natively; don't build a separate custom save path

---

## Phase 8 — Delete Message (Self / Everyone)

No backend changes — existing rules already enforce this correctly for any authenticated client.

- [ ] Long-press context menu on message bubbles (own and others')
- [ ] "Delete for me": add the caller's own uid to `deletedFor`; client filters out any message containing the viewer's own uid on render
- [ ] "Delete for everyone" (sender-only, unrestricted by time): clear content fields, set `deletedForEveryone: true` and `deletedAt`; for media, also delete the Storage blob
- [ ] Render tombstoned messages as "This message was deleted" for both participants

---

## Phase 9 — Read Receipts

No backend changes — existing rules already enforce this correctly.

- [ ] Mark a message read when its bubble actually becomes visible on screen (skip the viewer's own messages, already-read messages, and tombstoned ones) — Compose's equivalent of iOS's "mark read in a lazy list item's onAppear," e.g. via a visibility-tracking modifier on `LazyColumn` items
- [ ] Double-checkmark indicator on the sender's own messages only: gray/dim while unread, blue once the other participant's uid appears in `readBy`

---

## Phase 10 — Storage & Firestore Security Rules

- [ ] Confirm the already-deployed `firebase/SecurityRules/firestore.rules` and `storage.rules` need no Android-specific changes — they're written generically against Firebase Auth uids and Firestore/Storage semantics, not anything iOS-specific, so this should be a verification step, not new rules work
- [ ] `[HUMAN]` Confirm that verification after real end-to-end testing (Phase 4/12), not just by reading the rules

---

## Phase 11 — Material Design UI Pass

- [ ] `[HUMAN]` Decide: closely match iOS's visual language (same accent color, same bubble conventions) for cross-platform brand consistency, or follow platform-native Material 3 conventions instead
- [ ] Chat list: avatar placeholder, name (admin `displayId` or uid fallback), last-message preview, timestamp
- [ ] Chat thread: sent/received bubble styling and alignment, date separators, read-receipt icons
- [ ] Bottom input bar: text field, camera icon, gallery icon, send button
- [ ] Media bubble styling + tap-to-fullscreen viewer (Phase 7)
- [ ] `[HUMAN]` Visual QA pass

---

## Phase 12 — Hardening & QA

- [ ] Decrypted-media cache retention policy — default to matching iOS (evict after 30 days, re-decrypt on demand) unless there's a reason to diverge
- [ ] `[HUMAN]` End-to-end test: single-device kickout
- [ ] `[HUMAN]` End-to-end test: **cross-platform pairing** (Android ↔ iOS) and re-pairing/key-versioning
- [ ] `[HUMAN]` End-to-end test: passcode lockout timing/reset
- [ ] `[HUMAN]` End-to-end test: delete-for-self vs. delete-for-everyone, cross-platform (sent from one OS, deleted from the other)
- [ ] `[HUMAN]` End-to-end test: read receipts, cross-platform
- [ ] `[HUMAN]` Manual security review: confirm no plaintext keys, passcodes, or decrypted media are ever written to Firestore, Storage, or logs

---

## Phase 13 — Play Store / Internal Testing Delivery

- [ ] `[HUMAN]` Google Play Console account, app listing
- [ ] `[HUMAN]` Set up an internal testing track
- [ ] `[HUMAN]` Generate and manage a signing key
- [ ] `[HUMAN]` Write test instructions (flag that pairing requires two physical devices in person, same as iOS)
- [ ] `[HUMAN]` Collect and triage feedback, iterate
