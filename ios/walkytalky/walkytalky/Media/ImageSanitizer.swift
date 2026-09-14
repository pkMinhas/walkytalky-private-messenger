import ImageIO
import UIKit
import UniformTypeIdentifiers

enum ImageSanitizer {
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
