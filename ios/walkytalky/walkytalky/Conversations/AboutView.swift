import SwiftUI

/// App identity plus links to the developer's site and GitHub profile,
/// opened externally via `Link` (Safari/the system browser) — this view
/// never fetches or embeds either page itself.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

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
        }
    }
}

#Preview {
    AboutView()
}
