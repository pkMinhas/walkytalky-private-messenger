import CoreGraphics

/// Pure geometry for the fullscreen pager's pinch-zoom/pan: how far a
/// `.scaledToFit()` image can pan at a given zoom level before its edge
/// reaches its container's edge. Extracted from `MediaPagerView` so the
/// boundary math — the trigger for "pan past the edge hands off into a
/// page turn" — can be tested without driving an actual gesture.
enum ZoomPanMath {
    static func maxPanOffset(imageSize: CGSize, containerSize: CGSize, scale: CGFloat) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        let fitSize = imageAspect > containerAspect
            ? CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
            : CGSize(width: containerSize.height * imageAspect, height: containerSize.height)

        let scaledSize = CGSize(width: fitSize.width * scale, height: fitSize.height * scale)
        return CGSize(
            width: max(0, (scaledSize.width - containerSize.width) / 2),
            height: max(0, (scaledSize.height - containerSize.height) / 2)
        )
    }
}
