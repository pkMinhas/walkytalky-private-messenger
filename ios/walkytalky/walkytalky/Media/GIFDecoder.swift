import ImageIO
import UIKit
import UniformTypeIdentifiers

/// A decoded image ready for display: either a single static frame, or
/// every frame of an animated GIF plus its own per-frame delay. Produced by
/// `MediaDecryptor`, consumed by `MediaImageView` everywhere the app shows
/// decrypted media, so the animate-or-not decision is made once, at decode
/// time, rather than duplicated at each call site.
///
/// `nonisolated` because this (like the rest of `MediaDecryptor`'s pipeline
/// — download, decrypt, decode) is pure data work with no UI-thread
/// requirement; the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
/// setting would otherwise pin it to the main actor by default, which is
/// both wrong (it'd force decode work onto the main thread) and, for the
/// `single` factory specifically, fails to compile at all when referenced
/// as a bare function value from a nonisolated context.
nonisolated struct DecodedMedia {
    let frames: [UIImage]
    let frameDelays: [TimeInterval]

    static func single(_ image: UIImage) -> DecodedMedia {
        DecodedMedia(frames: [image], frameDelays: [0])
    }

    /// The frame used wherever only one representative image makes sense —
    /// the share sheet preview, most notably, since sharing an animating
    /// `Image` isn't a thing SwiftUI supports.
    var primaryImage: UIImage { frames[0] }
}

/// Decodes every frame of an animated GIF. Plain `UIImage(data:)` only ever
/// surfaces a GIF's first frame — SwiftUI's `Image` has no concept of an
/// animated `UIImage` either — so an animated GIF needs its frames pulled
/// out individually via ImageIO for `MediaImageView` to actually animate it.
nonisolated enum GIFDecoder {
    static func decode(_ data: Data) -> DecodedMedia? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }

        var frames: [UIImage] = []
        var delays: [TimeInterval] = []
        frames.reserveCapacity(frameCount)
        delays.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            delays.append(frameDelay(source: source, index: index))
        }

        guard !frames.isEmpty else { return nil }
        return DecodedMedia(frames: frames, frameDelays: delays)
    }

    /// GIF permits a per-frame delay of 0 (or omits it entirely); real-world
    /// decoders (browsers included) treat anything under ~0.02s as if it
    /// were the de facto default of 0.1s, since a literal 0 would spin the
    /// animation far faster than any GIF actually intends.
    private static func frameDelay(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        else { return 0.1 }

        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? TimeInterval
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime as String] as? TimeInterval
        let delay = unclamped ?? clamped ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }

    /// The inverse of `decode(_:)` — re-encodes a frame+delay sequence back
    /// into real GIF container bytes. Used by `FaceBlurService` to rebuild
    /// a GIF after blurring each frame individually, since Vision/CoreImage
    /// operate on plain `UIImage`s, not the GIF container itself.
    static func encode(frames: [UIImage], delays: [TimeInterval]) -> Data? {
        guard !frames.isEmpty, frames.count == delays.count else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.gif.identifier as CFString, frames.count, nil
        ) else { return nil }

        // Loop forever, matching how GIFs are conventionally authored when
        // there's no source loop count to preserve (we're building this GIF
        // fresh from frames, not copying an existing container).
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0],
        ] as CFDictionary)

        for (frame, delay) in zip(frames, delays) {
            guard let cgImage = frame.cgImage else { return nil }
            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: delay],
            ]
            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
