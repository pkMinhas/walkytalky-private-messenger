import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var directory: ParticipantDirectory
    @StateObject private var conversationsService = ConversationsService()
    @State private var showChangePasscode = false
    @State private var showMyUserID = false

    private var myUid: String {
        if case .signedIn(let uid) = authService.authState { return uid }
        return ""
    }

    var body: some View {
        NavigationStack {
            Group {
                if conversationsService.conversations.isEmpty {
                    ContentUnavailableView {
                        Label("No conversations yet", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("An admin needs to pair you with a contact first.")
                    } actions: {
                        Button("View My User ID") { showMyUserID = true }
                    }
                } else {
                    List(conversationsService.conversations) { conversation in
                        NavigationLink(value: conversation) {
                            ConversationRow(conversation: conversation, myUid: myUid)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Chats")
            .navigationDestination(for: Conversation.self) { conversation in
                ChatThreadView(conversation: conversation)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("My User ID") { showMyUserID = true }
                        Button("Change Passcode") { showChangePasscode = true }
                        Button("Sign Out", role: .destructive) {
                            Task { await authService.signOut() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showChangePasscode) {
                NavigationStack { ChangePasscodeView() }
            }
            .sheet(isPresented: $showMyUserID) {
                MyUserIDView(uid: myUid)
            }
        }
        .onAppear {
            guard !myUid.isEmpty else { return }
            conversationsService.startListening(uid: myUid)
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let myUid: String
    @EnvironmentObject private var directory: ParticipantDirectory
    @EnvironmentObject private var lastMessages: LastMessageDirectory

    private var otherUid: String? {
        conversation.otherParticipant(myUid: myUid)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let timestamp {
                Text(timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            if let otherUid, let id = conversation.id { directory.resolve(otherUid, in: id) }
            if let id = conversation.id { lastMessages.startListening(conversationId: id) }
        }
    }

    private var title: String {
        guard let otherUid else { return "Conversation" }
        return directory.displayName(for: otherUid)
    }

    private var preview: String {
        guard let id = conversation.id, let text = lastMessages.preview(for: id) else {
            return "No messages yet"
        }
        return text
    }

    private var timestamp: Date? {
        conversation.id.flatMap { lastMessages.timestamp(for: $0) }
    }
}

#Preview {
    ChatListView()
        .environmentObject(AuthService())
        .environmentObject(ParticipantDirectory())
        .environmentObject(LastMessageDirectory())
}
