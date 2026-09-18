import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// On-device face detection + blur — the actual mechanism behind "No Face"
/// mode. Runs entirely locally via Vision; no image data leaves the device
/// for detection, matching the app's E2E design (encryption happens after
/// this, never before).
///
/// `nonisolated`: this is pure CPU/ML work with no UI-thread requirement,
/// and the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting
/// would otherwise pin it to the main actor by default — the same class of
/// bug fixed earlier for `DecodedMedia`/`GIFDecoder`. `MediaUploadService`
/// dispatches this to a detached task specifically so a face-heavy photo
/// doesn't stall the UI while it runs.
nonisolated enum FaceBlur {
    enum BlurError: Error {
        case detectionFailed
    }

    /// Returns a copy of `image` with every detected face heavily blurred.
    /// Returns `image` unchanged (not an error) if detection succeeds but
    /// finds no faces — there's nothing to protect. Throws only when
    /// detection or re-rendering itself genuinely fails, so a caller in a
    /// privacy-sensitive context (see `FaceBlurService`) can fail closed
    /// instead of silently sending an unprotected original.
    static func blurringFaces(in image: UIImage) throws -> UIImage {
        // Normalize orientation into the pixel buffer first — Vision's
        // face rectangles and CoreImage's compositing both need to agree
        // on the same upright coordinate space, and a raw CGImage has no
        // orientation of its own (same reasoning as `ImageSanitizer`'s
        // metadata stripping, reused here rather than re-derived).
        guard let normalized = ImageSanitizer.normalizedCGImage(from: image) else {
            throw BlurError.detectionFailed
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: normalized, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            throw BlurError.detectionFailed
        }

        guard let faces = request.results, !faces.isEmpty else { return image }

        let sourceImage = CIImage(cgImage: normalized)
        let extent = sourceImage.extent
        var composited = sourceImage
        let context = CIContext()

        for face in faces {
            // Vision's normalized boundingBox and CIImage's pixel space are
            // both bottom-left-origin, so this maps directly with no
            // manual flip needed.
            let faceRect = VNImageRectForNormalizedRect(face.boundingBox, Int(extent.width), Int(extent.height))
            // A small pad past Vision's box so the blur edge doesn't cut
            // through the face itself, without ballooning out over
            // hair/shoulders/background the way a larger pad would.
            let pad = 0.1
            let blurRegion = faceRect
                .insetBy(dx: -faceRect.width * pad, dy: -faceRect.height * pad)
                .intersection(extent)
            guard !blurRegion.isEmpty else { continue }

            let blurFilter = CIFilter.gaussianBlur()
            // Clamp before blurring so the filter doesn't sample
            // transparent/black pixels from outside the image at the
            // region's edges.
            blurFilter.inputImage = sourceImage.clampedToExtent()
            // Scaled to the face's own size (not the whole photo's), so a
            // close-up face gets a proportionally strong, identity-
            // obscuring blur regardless of overall image resolution.
            blurFilter.radius = Float(max(blurRegion.width, blurRegion.height) * 0.35)

            guard let blurredRegion = blurFilter.outputImage?.cropped(to: blurRegion) else { continue }
            composited = blurredRegion.composited(over: composited)
        }

        guard let outputCGImage = context.createCGImage(composited, from: extent) else {
            throw BlurError.detectionFailed
        }
        return UIImage(cgImage: outputCGImage)
    }
}

/// Applies `FaceBlur` to a whole media payload before it's ever encrypted,
/// gated per-conversation by `NoFaceModeStore`. Static images are blurred
/// once; GIFs are decoded, blurred frame-by-frame (a face can move or
/// simply persist across every frame it appears in), and re-encoded.
nonisolated enum FaceBlurService {
    enum ProcessingError: Error {
        case failed
    }

    static func apply(to data: Data, type: MessageType) throws -> Data {
        switch type {
        case .text:
            return data

        case .image:
            guard let image = UIImage(data: data) else { throw ProcessingError.failed }
            let blurred = try FaceBlur.blurringFaces(in: image)
            guard let jpeg = blurred.jpegData(compressionQuality: 0.95) else { throw ProcessingError.failed }
            return jpeg

        case .gif:
            guard let decoded = GIFDecoder.decode(data) else { throw ProcessingError.failed }
            let blurredFrames = try decoded.frames.map { try FaceBlur.blurringFaces(in: $0) }
            guard let encoded = GIFDecoder.encode(frames: blurredFrames, delays: decoded.frameDelays) else {
                throw ProcessingError.failed
            }
            return encoded
        }
    }
}
