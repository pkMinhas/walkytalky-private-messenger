import FirebaseStorage
import SwiftUI

/// Renders one media message bubble: downloads the ciphertext (once, then
/// caches the decrypted bytes in `MediaStorage`), decrypts it with the
/// matching `keyVersion` key, and displays it — from the app-private
/// sandbox only, never the system Photos library. Shows a placeholder if
/// the message pre-dates a re-pair and its key was discarded.
struct MediaMessageView: View {
    let message: Message
    let conversationId: String
    /// Show the save-to-gallery button. Task list scopes this to received
    /// media, so `ChatThreadView` passes `!isMine`.
    var allowSave: Bool = false

    @State private var uiImage: UIImage?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var saveState: SaveState = .idle
    @State private var showFullscreen = false

    private enum SaveState: Equatable {
        case idle, saving, saved
        case failed(String)
    }

    var body: some View {
        Group {
            if let uiImage {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { showFullscreen = true }

                    if allowSave {
                        saveButton(for: uiImage)
                            .padding(6)
                    }
                }
                .fullScreenCover(isPresented: $showFullscreen) {
                    FullscreenImageViewer(image: uiImage)
                }
                .alert(
                    "Couldn't Save",
                    isPresented: Binding(
                        get: { if case .failed = saveState { true } else { false } },
                        set: { if !$0 { saveState = .idle } }
                    )
                ) {
                    Button("OK") { saveState = .idle }
                } message: {
                    if case .failed(let text) = saveState {
                        Text(text)
                    }
                }
            } else if let errorText {
                VStack(spacing: 4) {
                    Image(systemName: "lock.slash")
                    Text(errorText)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 160, height: 120)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ProgressView()
                    .frame(width: 160, height: 120)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .task(id: message.id) {
            await load()
        }
    }

    private func load() async {
        guard let messageId = message.id else {
            errorText = "Can't display this message"
            return
        }

        if let cached = MediaStorage.read(messageId: messageId), let image = UIImage(data: cached) {
            uiImage = image
            return
        }

        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let storagePath = message.storagePath,
              let nonce = message.nonce,
              let keyVersion = message.keyVersion,
              let key = ConversationKeyStore.key(conversationId: conversationId, keyVersion: keyVersion)
        else {
            errorText = "Can't decrypt this message"
            return
        }

        do {
            let ref = Storage.storage().reference(withPath: storagePath)
            let downloaded = try await ref.data(maxSize: 25 * 1024 * 1024)
            let decrypted = try MediaCrypto.decrypt(downloaded, nonceBase64: nonce, key: key)
            try MediaStorage.write(decrypted, messageId: messageId)
            uiImage = UIImage(data: decrypted)
        } catch {
            errorText = "Can't decrypt this message"
        }
    }

    @ViewBuilder
    private func saveButton(for image: UIImage) -> some View {
        Button {
            saveToGallery(image)
        } label: {
            Group {
                switch saveState {
                case .saving:
                    ProgressView()
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                default:
                    Image(systemName: "square.and.arrow.down.fill")
                }
            }
            .font(.system(size: 22))
            .foregroundStyle(.white, .black.opacity(0.4))
        }
        .disabled(saveState == .saving || saveState == .saved)
    }

    private func saveToGallery(_ image: UIImage) {
        saveState = .saving
        Task {
            do {
                try await GallerySaver.save(image)
                saveState = .saved
            } catch {
                saveState = .failed(error.localizedDescription)
            }
        }
    }
}

/// Tap-to-fullscreen viewer with pinch-to-zoom and double-tap-to-reset.
private struct FullscreenImageViewer: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in scale = lastScale * value }
                        .onEnded { _ in lastScale = max(scale, 1) }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        scale = 1
                        lastScale = 1
                    }
                }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
        }
    }
}
