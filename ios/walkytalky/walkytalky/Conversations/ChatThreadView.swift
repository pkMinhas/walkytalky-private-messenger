import SwiftUI

struct ChatThreadView: View {
    let conversation: Conversation

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var directory: ParticipantDirectory
    @StateObject private var messagesService = MessagesService()
    @StateObject private var uploadService = MediaUploadService()
    @State private var draft = ""
    @State private var showPairing = false
    @State private var isPaired = false
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var showMediaGrid = false
    @State private var noFaceModeEnabled = false
    @State private var browserURL: BrowserURL?
    @State private var lastFailedUpload: (data: Data, type: MessageType)?
    @State private var sendErrorMessage: String?

    private var myUid: String {
        if case .signedIn(let uid) = authService.authState { return uid }
        return ""
    }

    private var otherUid: String? {
        conversation.otherParticipant(myUid: myUid)
    }

    /// "Delete for me" filters client-side: a message containing the
    /// viewer's own uid in `deletedFor` never renders for them, per spec.
    private var visibleMessages: [Message] {
        messagesService.messages.filter { !$0.deletedFor.contains(myUid) }
    }

    /// Every non-deleted photo/GIF in the conversation, oldest first —
    /// matches thread order, so paging forward in the gallery moves toward
    /// more recent media just like scrolling down the thread would.
    private var mediaMessages: [Message] {
        visibleMessages.filter { ($0.type == .image || $0.type == .gif) && !$0.deletedForEveryone }
    }

    private var threadRows: [ThreadRow] {
        var rows: [ThreadRow] = []
        var lastDay: Date?
        for message in visibleMessages {
            if let createdAt = message.createdAt {
                let day = Calendar.current.startOfDay(for: createdAt)
                if day != lastDay {
                    rows.append(.daySeparator(day))
                    lastDay = day
                }
            }
            rows.append(.message(message))
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isPaired {
                Button {
                    showPairing = true
                } label: {
                    Label("Not paired — tap to pair before messaging", systemImage: "qrcode")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.2))
            }

            if let listenErrorMessage = messagesService.listenErrorMessage {
                Label("Couldn't load messages: \(listenErrorMessage)", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(threadRows) { row in
                            switch row {
                            case .daySeparator(let day):
                                DaySeparatorView(date: day)
                            case .message(let message):
                                MessageBubble(
                                    message: message,
                                    isMine: message.senderId == myUid,
                                    conversationId: conversation.id ?? "",
                                    isReadByOther: otherUid.map { message.readBy.contains($0) } ?? false,
                                    mediaMessages: mediaMessages
                                )
                                .id(message.id)
                                .onAppear { markReadIfNeeded(message) }
                                .contextMenu {
                                    Button("Delete for Me", role: .destructive) {
                                        deleteForMe(message)
                                    }
                                    if message.senderId == myUid && !message.deletedForEveryone {
                                        Button("Delete for Everyone", role: .destructive) {
                                            deleteForEveryone(message)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .onChange(of: visibleMessages.count) { _, _ in
                    guard let lastId = visibleMessages.last?.id else { return }
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            Divider()

            uploadStatusBar

            HStack(spacing: 8) {
                Button {
                    if isPaired { showCamera = true } else { showPairing = true }
                } label: {
                    Image(systemName: "camera")
                }
                Button {
                    if isPaired { showGallery = true } else { showPairing = true }
                } label: {
                    Image(systemName: "photo.on.rectangle")
                }
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            if noFaceModeEnabled {
                Text("Enhanced privacy: images will have faces blurred before sending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .alert("Couldn't Send", isPresented: sendErrorBinding) {
            Button("OK") { sendErrorMessage = nil }
        } message: {
            Text(sendErrorMessage ?? "")
        }
        .navigationTitle(otherUid.map { directory.displayName(for: $0, in: conversation.id ?? "") } ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showMediaGrid = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    toggleNoFaceMode()
                } label: {
                    ZStack {
                        Image(systemName: "face.dashed")
                        if noFaceModeEnabled {
                            Image(systemName: "slash.circle")
                        }
                    }
                    
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showPairing = true
                } label: {
                    Image(systemName: isPaired ? "checkmark.shield" : "qrcode")
                }
            }
        }
        // Scoped to this conversation, not app-wide: links tapped in a
        // message bubble get routed to the private in-app browser instead
        // of the system browser. Non-http(s) schemes (mailto:, tel:, etc.)
        // fall through to the system as normal — an in-app web browser
        // can't sensibly handle those anyway.
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "http" || url.scheme == "https" else {
                return .systemAction
            }
            browserURL = BrowserURL(url: url)
            return .handled
        })
        .sheet(isPresented: $showPairing, onDismiss: refreshPairingState) {
            PairingView(conversation: conversation)
        }
        .sheet(isPresented: $showMediaGrid) {
            MediaGalleryView(mediaMessages: mediaMessages, conversationId: conversation.id ?? "")
        }
        .fullScreenCover(item: $browserURL) { wrapper in
            InAppBrowserView(url: wrapper.url)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(
                onCapture: { image in
                    showCamera = false
                    if let data = image.jpegData(compressionQuality: 0.9) {
                        uploadMedia(data: data, type: .image)
                    }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showGallery) {
            GalleryPickerView(
                onPick: { data, type in
                    showGallery = false
                    uploadMedia(data: data, type: type)
                },
                onCancel: { showGallery = false }
            )
        }
        .onAppear {
            if let otherUid, let id = conversation.id { directory.resolve(otherUid, in: id) }
            guard let id = conversation.id else { return }
            messagesService.startListening(conversationId: id)
            refreshPairingState()
            noFaceModeEnabled = NoFaceModeStore.isEnabled(conversationId: id)
        }
        .onDisappear {
            messagesService.stopListening()
        }
    }

    private func refreshPairingState() {
        guard let id = conversation.id else {
            isPaired = false
            return
        }
        isPaired = ConversationKeyStore.currentKey(conversationId: id) != nil
    }

    /// No Face mode is local to this device — toggling it here only
    /// changes how *this device* processes media it sends going forward;
    /// it isn't synced to Firestore and the other participant has no way
    /// to see or affect it.
    private func toggleNoFaceMode() {
        guard let id = conversation.id else { return }
        noFaceModeEnabled.toggle()
        NoFaceModeStore.setEnabled(noFaceModeEnabled, conversationId: id)
    }

    private func send() {
        guard let id = conversation.id, !myUid.isEmpty else { return }
        guard isPaired else {
            showPairing = true
            return
        }
        let text = draft
        draft = ""
        Task {
            do {
                try await messagesService.sendText(conversationId: id, senderId: myUid, text: text)
            } catch {
                draft = text
                sendErrorMessage = error.localizedDescription
            }
        }
    }

    private var sendErrorBinding: Binding<Bool> {
        Binding(
            get: { sendErrorMessage != nil },
            set: { if !$0 { sendErrorMessage = nil } }
        )
    }

    @ViewBuilder
    private var uploadStatusBar: some View {
        switch uploadService.state {
        case .idle:
            EmptyView()
        case .uploading(let progress):
            ProgressView(value: progress)
                .padding(.horizontal)
                .padding(.top, 4)
        case .failed(let message):
            HStack {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                Spacer()
                Button("Retry") {
                    guard let pending = lastFailedUpload else { return }
                    uploadMedia(data: pending.data, type: pending.type)
                }
                .font(.footnote)
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }

    private func uploadMedia(data: Data, type: MessageType) {
        guard let id = conversation.id, !myUid.isEmpty else { return }
        lastFailedUpload = nil
        Task {
            await uploadService.send(imageData: data, type: type, conversationId: id, senderId: myUid)
            if case .failed = uploadService.state {
                lastFailedUpload = (data, type)
            }
        }
    }

    private func deleteForMe(_ message: Message) {
        guard let id = conversation.id, let messageId = message.id, !myUid.isEmpty else { return }
        Task {
            try? await messagesService.deleteForMe(conversationId: id, messageId: messageId, uid: myUid)
        }
    }

    private func deleteForEveryone(_ message: Message) {
        guard let id = conversation.id else { return }
        Task {
            try? await messagesService.deleteForEveryone(conversationId: id, message: message)
        }
    }

    private func markReadIfNeeded(_ message: Message) {
        guard let id = conversation.id,
              let messageId = message.id,
              !myUid.isEmpty,
              message.senderId != myUid,
              !message.readBy.contains(myUid),
              !message.deletedForEveryone
        else { return }
        Task {
            try? await messagesService.markRead(conversationId: id, messageId: messageId, uid: myUid)
        }
    }
}

private struct BrowserURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private enum ThreadRow: Identifiable {
    case message(Message)
    case daySeparator(Date)

    var id: String {
        switch self {
        case .message(let message): message.id ?? UUID().uuidString
        case .daySeparator(let date): "separator-\(date.timeIntervalSince1970)"
        }
    }
}

private struct DaySeparatorView: View {
    let date: Date

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private var text: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct MessageBubble: View {
    let message: Message
    let isMine: Bool
    let conversationId: String
    /// Whether the other participant has this uid in `readBy`. Only
    /// meaningful (and only rendered) for messages this device sent.
    let isReadByOther: Bool
    /// Passed through to `MediaMessageView` so its fullscreen viewer can
    /// page through every media message in the conversation, not just
    /// this bubble's own image.
    let mediaMessages: [Message]

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }

            if message.deletedForEveryone {
                Text("This message was deleted")
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                messageContent
            }

            if !isMine { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
            switch message.type {
            case .text:
                VStack(alignment: .leading, spacing: 2) {
                    Text(LinkDetector.attributedString(from: message.decryptedText(conversationId: conversationId)))
                    HStack(spacing: 4) {
                        Text(timeText)
                            .font(.caption2)
                            .foregroundStyle(isMine ? .white.opacity(0.7) : .secondary)
                        if isMine {
                            readReceiptIcon()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isMine ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isMine ? Color.white : Color.primary)
                .clipShape(bubbleShape)

            case .image, .gif:
                VStack(alignment: .leading, spacing: 2) {
                    MediaMessageView(message: message, conversationId: conversationId, mediaMessages: mediaMessages)
                    HStack(spacing: 4) {
                        Text(timeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if isMine {
                            readReceiptIcon(fgColor: .secondary)
                        }
                    }
                }
            }
    }

    private var timeText: String {
        guard let date = message.createdAt else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Read receipt, shown only on the sender's own messages: a single
    /// checkmark once sent, a second one once the other participant's uid
    /// appears in `readBy`.
    @ViewBuilder
    private func readReceiptIcon(fgColor : Color = .white) -> some View {
        HStack(spacing: -5) {
            Image(systemName: "checkmark")
            if isReadByOther {
                Image(systemName: "checkmark")
            }
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(fgColor)
        .accessibilityLabel(isReadByOther ? "Read" : "Sent")
    }

    /// A flattened corner on the sender's side gives the bubble a WhatsApp-
    /// style tail without needing a custom `Path`.
    private var bubbleShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: isMine ? 16 : 4,
            bottomTrailingRadius: isMine ? 4 : 16,
            topTrailingRadius: 16
        )
    }
}

#Preview {
    NavigationStack {
        ChatThreadView(conversation: Conversation(participants: ["a", "b"]))
    }
    .environmentObject(AuthService())
    .environmentObject(ParticipantDirectory())
}
