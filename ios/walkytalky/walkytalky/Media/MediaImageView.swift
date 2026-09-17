import SwiftUI

/// Displays a `DecodedMedia` — a drop-in replacement for
/// `Image(uiImage:).resizable()` wherever the app shows decrypted media.
/// Callers still chain `.scaledToFit()` / `.scaledToFill()` / `.frame()`
/// afterward exactly as before; `.resizable()` is applied internally since
/// it's an `Image`-only modifier. A static image renders as a plain
/// `Image`; an animated one cycles its frames over time via `TimelineView`,
/// which SwiftUI's `Image` cannot do on its own for a multi-frame `UIImage`.
///
/// When `showsPlaybackControl` is set (the chat bubble and grid thumbnails;
/// left off for the fullscreen pager, which wasn't asked for this), an
/// animated image gets a small play/pause button overlaid in the corner.
/// `TimelineView` has no built-in pause, so playback position is tracked as
/// accumulated elapsed time plus an in-progress session, frozen and resumed
/// only from the button's own action — never from inside the `TimelineView`
/// closure, which SwiftUI re-invokes far too often to safely mutate state
/// from.
struct MediaImageView: View {
    let media: DecodedMedia
    var showsPlaybackControl: Bool = false

    @State private var isPlaying = true
    @State private var accumulatedPlayTime: TimeInterval = 0
    @State private var playSessionStart = Date()

    private var isAnimated: Bool { media.frames.count > 1 }
    private var totalDuration: TimeInterval { media.frameDelays.reduce(0, +) }

    var body: some View {
        content
            .overlay(alignment: .bottomLeading) {
                if isAnimated && showsPlaybackControl {
                    PlayPauseButton(isPlaying: isPlaying, action: togglePlayback)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if isAnimated {
            TimelineView(.animation) { context in
                let elapsed = isPlaying
                    ? accumulatedPlayTime + context.date.timeIntervalSince(playSessionStart)
                    : accumulatedPlayTime
                Image(uiImage: media.frames[frameIndex(forElapsed: elapsed)])
                    .resizable()
            }
        } else {
            Image(uiImage: media.primaryImage)
                .resizable()
        }
    }

    private func togglePlayback() {
        let now = Date()
        if isPlaying {
            accumulatedPlayTime += now.timeIntervalSince(playSessionStart)
        } else {
            playSessionStart = now
        }
        isPlaying.toggle()
    }

    private func frameIndex(forElapsed totalElapsed: TimeInterval) -> Int {
        guard totalDuration > 0 else { return 0 }
        let elapsed = totalElapsed.truncatingRemainder(dividingBy: totalDuration)
        var accumulated: TimeInterval = 0
        for (index, delay) in media.frameDelays.enumerated() {
            accumulated += delay
            if elapsed < accumulated { return index }
        }
        return media.frames.count - 1
    }
}

private struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.55), in: Circle())
        }
        .padding(6)
    }
}
