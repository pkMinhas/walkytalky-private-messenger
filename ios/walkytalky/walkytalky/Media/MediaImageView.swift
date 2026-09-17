import SwiftUI

/// Displays a `DecodedMedia` — a drop-in replacement for
/// `Image(uiImage:).resizable()` wherever the app shows decrypted media.
/// Callers still chain `.scaledToFit()` / `.scaledToFill()` / `.frame()`
/// afterward exactly as before; `.resizable()` is applied internally since
/// it's an `Image`-only modifier. A static image renders as a plain
/// `Image`; an animated one cycles its frames over time via `TimelineView`,
/// which SwiftUI's `Image` cannot do on its own for a multi-frame `UIImage`.
struct MediaImageView: View {
    let media: DecodedMedia

    private var totalDuration: TimeInterval { media.frameDelays.reduce(0, +) }

    var body: some View {
        if media.frames.count <= 1 {
            Image(uiImage: media.primaryImage)
                .resizable()
        } else {
            TimelineView(.animation) { context in
                Image(uiImage: media.frames[frameIndex(at: context.date)])
                    .resizable()
            }
        }
    }

    private func frameIndex(at date: Date) -> Int {
        guard totalDuration > 0 else { return 0 }
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: totalDuration)
        var accumulated: TimeInterval = 0
        for (index, delay) in media.frameDelays.enumerated() {
            accumulated += delay
            if elapsed < accumulated { return index }
        }
        return media.frames.count - 1
    }
}
