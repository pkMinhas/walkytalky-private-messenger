import FirebaseStorage
import SwiftUI

/// Renders one media message bubble: downloads the ciphertext (once, then
/// caches the decrypted bytes in `MediaStorage`), decrypts it with the
/// matching `keyVersion` key, and displays it — from the app-private
/// sandbox only, never the system Photos library. Shows a placeholder if
/// the message pre-dates a re-pair and its key was discarded. Tapping the
/// thumbnail opens a fullscreen viewer with zoom/pan and a share button —
/// that share sheet's own "Save Image" action is how a decrypted photo
/// reaches the system Photo Library now, so this view has no save button
/// of its own.
struct MediaMessageView: View {
    let message: Message
    let conversationId: String

    @State private var uiImage: UIImage?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showFullscreen = false

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { showFullscreen = true }
                    .fullScreenCover(isPresented: $showFullscreen) {
                        FullscreenImageViewer(image: uiImage)
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
}

/// Fullscreen viewer: pinch to zoom, drag to pan while zoomed in, double-tap
/// to toggle zoom, and a share button (top trailing) that hands the
/// decrypted image to the system share sheet — AirDrop, Messages, Save
/// Image, etc. all come from there for free.
private struct FullscreenImageViewer: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, lastScale * value)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= 1 {
                                    withAnimation { resetTransform() }
                                }
                            },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        if scale > 1 {
                            resetTransform()
                        } else {
                            scale = 2
                            lastScale = 2
                        }
                    }
                }
        }
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                Spacer()
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview("Photo", image: Image(uiImage: image))
                ) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
            }
            .padding()
        }
    }

    private func resetTransform() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
