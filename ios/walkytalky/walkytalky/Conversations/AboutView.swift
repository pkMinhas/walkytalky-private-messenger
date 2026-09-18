import SwiftUI
import UserNotifications

/// App identity plus links to the developer's site and GitHub profile,
/// opened externally via `Link` (Safari/the system browser) — this view
/// never fetches or embeds either page itself.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    #if DEBUG
    @State private var authorizationStatus: UNAuthorizationStatus?
    @State private var debugTriggerResult: String?
    @State private var isRunningDebugTrigger = false
    #endif

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("walkytalky")
                    .font(.title2.weight(.semibold))
                Text("Version \(appVersion)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("A self-hosted, end-to-end encrypted chat app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    Link(destination: URL(string: "https://withpreet.com")!) {
                        Label("withpreet.com", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Link(destination: URL(string: "https://github.com/pkminhas")!) {
                        Label("github.com/pkminhas", systemImage: "chevron.left.slash.chevron.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 32)

                #if DEBUG
                debugBackgroundCheckSection
                #endif

                Spacer()
            }
            .padding(.vertical)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            #if DEBUG
            .task {
                authorizationStatus = await BackgroundMessageChecker.authorizationStatus()
            }
            #endif
        }
    }

    #if DEBUG
    /// Debug-only: lets the check-and-notify logic be exercised directly
    /// instead of waiting on iOS's own opportunistic `BGAppRefreshTask`
    /// scheduling, which can take hours or (in the Simulator, without the
    /// `_simulateLaunchForTaskWithIdentifier:` LLDB command) never happen
    /// at all — useful for telling apart "the code is broken" from "iOS
    /// just hasn't run it yet."
    @ViewBuilder
    private var debugBackgroundCheckSection: some View {
        VStack(spacing: 8) {
            Divider()
            Text("Debug: Background Message Check")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let authorizationStatus {
                Text("Notification permission: \(authorizationStatus.debugDescription)")
                    .font(.caption)
                    .foregroundStyle(authorizationStatus == .authorized ? Color.secondary : Color.red)
            }

            Button {
                isRunningDebugTrigger = true
                debugTriggerResult = nil
                Task {
                    let foundNew = await BackgroundMessageChecker.debugTriggerNow()
                    debugTriggerResult = foundNew
                        ? "Found a new message — notification posted."
                        : "No new messages found since the last checkpoint."
                    isRunningDebugTrigger = false
                }
            } label: {
                if isRunningDebugTrigger {
                    ProgressView()
                } else {
                    Text("Trigger Background Check Now")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRunningDebugTrigger)

            if let debugTriggerResult {
                Text(debugTriggerResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
    }
    #endif
}

#if DEBUG
extension UNAuthorizationStatus {
    fileprivate var debugDescription: String {
        switch self {
        case .authorized: "authorized"
        case .denied: "denied"
        case .notDetermined: "not determined"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }
}
#endif

#Preview {
    AboutView()
}
