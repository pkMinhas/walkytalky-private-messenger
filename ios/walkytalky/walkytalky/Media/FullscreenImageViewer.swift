import SwiftUI

/// Pinch-to-zoom, drag-to-pan, double-tap-to-toggle image content with no
/// chrome of its own — shared by the single-image `FullscreenImageViewer`
/// and each page of `MediaPagerView`.
struct ZoomableImage: View {
    let media: DecodedMedia

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        MediaImageView(media: media)
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

    private func resetTransform() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

/// Fullscreen viewer: pinch to zoom, drag to pan while zoomed in, double-tap
/// to toggle zoom, and a share button (top trailing) that hands the
/// decrypted image to the system share sheet — AirDrop, Messages, Save
/// Image, etc. all come from there for free. `pageInfo` (e.g. "2 of 5") is
/// shown centered in the top bar when this is one page of `MediaPagerView`;
/// leave it nil for the single-image case opened from a chat bubble.
struct FullscreenImageViewer: View {
    let media: DecodedMedia
    var pageInfo: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ZoomableImage(media: media)
        }
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                if let pageInfo {
                    Spacer()
                    Text(pageInfo)
                        .font(.footnote)
                        .foregroundStyle(.white)
                }
                Spacer()
                ShareLink(
                    item: Image(uiImage: media.primaryImage),
                    preview: SharePreview("Photo", image: Image(uiImage: media.primaryImage))
                ) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
            }
            .padding()
        }
    }
}
