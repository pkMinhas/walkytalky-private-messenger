import ImageIO
import UIKit
import UniformTypeIdentifiers

enum ImageSanitizer {
    /// 4K UHD's long edge — the common meaning of "4K" for a photo (which,
    /// unlike video, isn't fixed at 16:9). Only ever downscales; a smaller
    /// image is left at its original size.
    static let maxUploadDimension: CGFloat = 3840
    static let uploadJPEGQuality: CGFloat = 0.95

    /// Full prep pipeline for a non-GIF image message before encryption:
    /// normalize orientation, downscale to fit within `maxUploadDimension`
    /// (aspect ratio preserved, never upscaled), and encode as JPEG at
    /// `uploadJPEGQuality` — all in one redraw pass, so resizing doesn't
    /// compound with a separate lossy re-encode. GIFs skip this entirely
    /// (see `stripMetadata` below) since converting one to JPEG would
    /// destroy it.
    static func prepareImageForUpload(_ data: Data) -> Data? {
        guard let sourceImage = UIImage(data: data) else { return nil }
        let targetSize = scaledSize(for: sourceImage.size, maxDimension: maxUploadDimension)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // work in actual pixels, not points
        format.opaque = true // JPEG has no alpha channel
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        // `.draw(in:)` respects `imageOrientation` and scales to the
        // target rect in the same pass; the freshly rendered bitmap has no
        // attached metadata, so this also satisfies the "strip metadata"
        // requirement without a separate CGImageSource/Destination step.
        let normalized = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return normalized.jpegData(compressionQuality: uploadJPEGQuality)
    }

    private static func scaledSize(for size: CGSize, maxDimension: CGFloat) -> CGSize {
        let longerEdge = max(size.width, size.height)
        guard longerEdge > maxDimension else { return size }
        let scale = maxDimension / longerEdge
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Re-encodes image data with all metadata (EXIF, GPS, etc.) stripped.
    /// Decoding to a `CGImage` first (rather than
    /// `CGImageDestinationAddImageFromSource`, which would carry the
    /// source's metadata over) is what actually drops it — a `CGImage` is
    /// pixel data only, with no metadata dictionary attached.
    ///
    /// Orientation is normalized into the pixel buffer *before* that
    /// stripping, on purpose: a `CGImage` has no orientation of its own —
    /// many photos (especially camera captures, since the sensor itself is
    /// landscape-oriented) rely entirely on the EXIF orientation tag to
    /// display upright, with the raw pixel buffer left unrotated. Stripping
    /// metadata without accounting for that first would silently drop the
    /// tag and leave the image permanently sideways.
    ///
    /// A multi-frame source (an animated GIF) is detected and routed to
    /// `stripMetadataFromAnimatedSource` instead — the single-frame path
    /// below would otherwise silently flatten it to its first frame, which
    /// is what `UIImage(data:)` / a single `CGImageDestinationAddImage`
    /// call does with an animated source.
    static func stripMetadata(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let frameCount = CGImageSourceGetCount(source)
        if frameCount > 1 {
            return stripMetadataFromAnimatedSource(source, frameCount: frameCount)
        }

        guard let sourceImage = UIImage(data: data),
              let normalized = normalizedCGImage(from: sourceImage)
        else { return nil }

        let type = CGImageSourceGetType(source) ?? (UTType.jpeg.identifier as CFString)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }

        CGImageDestinationAddImage(destination, normalized, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Copies every frame of an animated (GIF) source into a fresh
    /// destination, preserving each frame's delay time and the source's
    /// loop count — the structural properties required for correct
    /// playback — while dropping everything else. Frames need no
    /// orientation-normalization pass the way single photos do; GIF has no
    /// EXIF-orientation concept.
    private static func stripMetadataFromAnimatedSource(_ source: CGImageSource, frameCount: Int) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.gif.identifier as CFString, frameCount, nil
        ) else { return nil }

        if let sourceProperties = CGImageSourceCopyProperties(source, nil) as? [String: Any],
           let gifProperties = sourceProperties[kCGImagePropertyGIFDictionary as String] as? [String: Any],
           let loopCount = gifProperties[kCGImagePropertyGIFLoopCount as String] {
            CGImageDestinationSetProperties(destination, [
                kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: loopCount],
            ] as CFDictionary)
        }

        for index in 0..<frameCount {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }

            var frameProperties: [String: Any] = [:]
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
               let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any],
               let delay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String]
                   ?? gifProperties[kCGImagePropertyGIFDelayTime as String] {
                frameProperties[kCGImagePropertyGIFDictionary as String] = [kCGImagePropertyGIFDelayTime as String: delay]
            }

            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Bakes `imageOrientation` into the pixel buffer via drawing (which
    /// respects it, unlike the raw buffer itself), so the result no longer
    /// depends on an EXIF tag to display correctly.
    private static func normalizedCGImage(from image: UIImage) -> CGImage? {
        guard image.imageOrientation != .up else { return image.cgImage }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return normalized.cgImage
    }
}
