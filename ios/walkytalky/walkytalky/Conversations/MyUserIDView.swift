import SwiftUI

/// Shows this account's Firebase uid so it can be handed to an admin, who
/// pairs users into a conversation by uid (conversations are created
/// out-of-band per the Phase 3 task list — there's no in-app invite flow).
struct MyUserIDView: View {
    let uid: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Share this ID with an admin so they can add you to a conversation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Text(uid)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button {
                    UIPasteboard.general.string = uid
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                Spacer()
            }
            .padding(.vertical)
            .navigationTitle("My User ID")
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
    MyUserIDView(uid: "abc123def456")
}
