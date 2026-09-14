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
    static func stripMetadata(from data: Data) -> Data? {
        guard let sourceImage = UIImage(data: data),
              let normalized = normalizedCGImage(from: sourceImage)
        else { return nil }

        let type = CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap { CGImageSourceGetType($0) } ?? UTType.jpeg.identifier as CFString
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }

        CGImageDestinationAddImage(destination, normalized, nil)
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
