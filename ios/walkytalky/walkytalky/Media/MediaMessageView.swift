import SwiftUI

/// Renders one media message bubble: decrypts (via `MediaDecryptor`, which
/// caches the plaintext in `MediaStorage`) and displays it — from the
/// app-private sandbox only, never the system Photos library. Shows a
/// placeholder if the message pre-dates a re-pair and its key was
/// discarded. Tapping the thumbnail opens the same paged `MediaPagerView`
/// used by the media grid, positioned at this message, so swiping left or
/// right from here moves through the rest of the conversation's media —
/// zoom/pan and a share button come along on every page too. That share
/// sheet's own "Save Image" action is how a decrypted photo reaches the
/// system Photo Library now, so this view has no save button of its own.
struct MediaMessageView: View {
    let message: Message
    let conversationId: String
    /// Every media message in the conversation, in thread order — lets the
    /// fullscreen viewer opened from here page through all of them, not
    /// just this one.
    let mediaMessages: [Message]

    @State private var media: DecodedMedia?
    @State private var errorText: String?
    @State private var showFullscreen = false

    /// Falls back to just this message if the caller couldn't supply the
    /// full list (or it's stale and no longer contains this message), so
    /// the viewer always has at least one page to show.
    private var pagerMessages: [Message] {
        mediaMessages.contains { $0.id == message.id } ? mediaMessages : [message]
    }

    private var startIndex: Int {
        pagerMessages.firstIndex { $0.id == message.id } ?? 0
    }

    var body: some View {
        Group {
            if let media {
                MediaImageView(media: media, showsPlaybackControl: true)
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { showFullscreen = true }
                    .fullScreenCover(isPresented: $showFullscreen) {
                        MediaPagerView(messages: pagerMessages, conversationId: conversationId, startIndex: startIndex)
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
            media = await MediaDecryptor.decryptedMedia(for: message, conversationId: conversationId)
            if media == nil {
                errorText = "Can't decrypt this message"
            }
        }
    }
}
