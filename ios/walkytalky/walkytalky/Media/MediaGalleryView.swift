import SwiftUI

/// Grid of every photo/GIF in a conversation, square-cropped thumbnails,
/// opened from `ChatThreadView`'s toolbar. Tapping a thumbnail opens
/// `MediaPagerView` at that item, from which the user can swipe left/right
/// to move through the rest of the conversation's media.
struct MediaGalleryView: View {
    let mediaMessages: [Message]
    let conversationId: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                if mediaMessages.isEmpty {
                    ContentUnavailableView("No Media Yet", systemImage: "photo.on.rectangle.angled")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(Array(mediaMessages.enumerated()), id: \.element.id) { index, message in
                                MediaGridThumbnail(message: message, conversationId: conversationId)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipped()
                                    .onTapGesture { selectedIndex = index }
                            }
                        }
                        .padding(2)
                    }
                }
            }
            .navigationTitle("Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: selectedIndexBinding) { selection in
            MediaPagerView(messages: mediaMessages, conversationId: conversationId, startIndex: selection.index)
        }
    }

    private var selectedIndexBinding: Binding<SelectedMediaIndex?> {
        Binding(
            get: { selectedIndex.map(SelectedMediaIndex.init) },
            set: { selectedIndex = $0?.index }
        )
    }
}

private struct SelectedMediaIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

/// One square grid cell: decrypts (and caches, via `MediaDecryptor`) its own
/// thumbnail independently of the pager, so opening the grid never blocks
/// on the full conversation's media loading serially.
private struct MediaGridThumbnail: View {
    let message: Message
    let conversationId: String

    @State private var media: DecodedMedia?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            Group {
                if let media {
                    MediaImageView(media: media, showsPlaybackControl: true)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if failed {
                    Image(systemName: "lock.slash")
                        .foregroundStyle(.secondary)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Color(.tertiarySystemBackground))
                } else {
                    ProgressView()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Color(.tertiarySystemBackground))
                }
            }
        }
        .task(id: message.id) {
            media = await MediaDecryptor.decryptedMedia(for: message, conversationId: conversationId)
            failed = media == nil
        }
    }
}

/// Paged fullscreen media viewer: swipe left/right to move between every
/// media message in the conversation, starting at `startIndex`; pinch to
/// zoom, drag to pan while zoomed, double-tap to toggle zoom, swipe down to
/// dismiss.
///
/// This deliberately doesn't use `TabView(.page)`: it can't be made to hand
/// off a pan gesture into a page turn once the user has panned to a zoomed
/// image's edge (which they asked for — dragging past a boundary should
/// keep moving into the next/previous photo, not just stop), and a second,
/// independent gesture recognizer for swipe-to-dismiss would fight
/// `TabView`'s own paging gesture for the same touch. So the whole
/// interaction — page-swipe, boundary hand-off, pinch/pan zoom, and
/// dismiss — is one gesture recognizer, owned here, with zoom state scoped
/// to whichever page is current (it resets on every page change, same as
/// most photo viewers).
struct MediaPagerView: View {
    let messages: [Message]
    let conversationId: String
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    /// Every page reports its decrypted media here as soon as it finishes
    /// decrypting — whether or not it's current yet, since a neighboring
    /// page is pre-loaded before the user swipes to it. `currentMedia`
    /// looks this up fresh rather than relying on a fire-once callback, so
    /// a page that was already loaded by the time it becomes current isn't
    /// left with no entry (which previously made the boundary math read
    /// "no pan room at all," triggering a page turn on any pan).
    @State private var loadedMedia: [String: DecodedMedia] = [:]

    private var currentMedia: DecodedMedia? {
        messages[currentIndex].id.flatMap { loadedMedia[$0] }
    }

    /// Live drag translation. `.width` drives the page-turn (and, while
    /// zoomed, carries only the pan's "overdrag" past its bounds, so the
    /// next/previous page previews sliding in under the finger). `.height`
    /// drives swipe-to-dismiss — only meaningful while not zoomed, since a
    /// vertical drag on a zoomed image pans it instead.
    @State private var dragTranslation: CGSize = .zero

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    init(messages: [Message], conversationId: String, startIndex: Int) {
        self.messages = messages
        self.conversationId = conversationId
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }

    private var isZoomed: Bool { scale > 1.01 }

    private var dismissProgress: Double {
        guard !isZoomed else { return 0 }
        return min(abs(dragTranslation.height) / 300, 1)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black
                    .opacity(1 - dismissProgress * 0.6)
                    .ignoresSafeArea()

                ForEach(visibleIndices, id: \.self) { index in
                    MediaPagerPage(
                        message: messages[index],
                        conversationId: conversationId,
                        scale: index == currentIndex ? scale : 1,
                        panOffset: index == currentIndex ? panOffset : .zero,
                        onLoaded: { media in
                            if let id = messages[index].id, let media {
                                loadedMedia[id] = media
                            }
                        }
                    )
                    .frame(width: size.width, height: size.height)
                    .offset(
                        x: CGFloat(index - currentIndex) * size.width + dragTranslation.width,
                        y: index == currentIndex ? dragTranslation.height : 0
                    )
                }

                chrome
                    .opacity(1 - dismissProgress)
            }
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1, lastScale * value)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1 { withAnimation { resetZoom() } }
                        },
                    DragGesture()
                        .onChanged { value in handleDragChanged(value, size: size) }
                        .onEnded { value in handleDragEnded(value, size: size) }
                )
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    if isZoomed { resetZoom() } else { scale = 2; lastScale = 2 }
                }
            }
        }
    }

    private var visibleIndices: [Int] {
        [currentIndex - 1, currentIndex, currentIndex + 1].filter { messages.indices.contains($0) }
    }

    /// Only the black background (below) explicitly ignores the safe area,
    /// so it fills edge-to-edge under the status bar/notch with no white
    /// gap; this overlay deliberately does *not*, so it gets normal
    /// safe-area padding from SwiftUI and sits below the status bar — a
    /// prior attempt at computing that inset manually via
    /// `geo.safeAreaInsets.top` didn't actually push the buttons down in
    /// practice, so this relies on SwiftUI's own layout instead of
    /// reimplementing it.
    @ViewBuilder
    private var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                if messages.count > 1 {
                    Spacer()
                    Text("\(currentIndex + 1) of \(messages.count)")
                        .font(.footnote)
                        .foregroundStyle(.white)
                }
                Spacer()
                if let currentMedia {
                    ShareLink(
                        item: Image(uiImage: currentMedia.primaryImage),
                        preview: SharePreview("Photo", image: Image(uiImage: currentMedia.primaryImage))
                    ) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                }
            }
            .padding()
            Spacer()
        }
    }

    /// How far the current page can pan at its current zoom level before
    /// its edge reaches the container's edge — the boundary that, once
    /// overdragged past, hands off into a page turn.
    private func maxPanOffset(size: CGSize) -> CGSize {
        guard let imageSize = currentMedia?.primaryImage.size else { return .zero }
        return ZoomPanMath.maxPanOffset(imageSize: imageSize, containerSize: size, scale: scale)
    }

    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
        guard isZoomed else {
            dragTranslation = value.translation
            return
        }

        let bounds = maxPanOffset(size: size)
        let proposed = CGSize(
            width: lastPanOffset.width + value.translation.width,
            height: lastPanOffset.height + value.translation.height
        )
        panOffset = CGSize(
            width: min(max(proposed.width, -bounds.width), bounds.width),
            height: min(max(proposed.height, -bounds.height), bounds.height)
        )
        // Whatever the pan couldn't absorb "bleeds" into a page-turn
        // preview — this is the boundary hand-off.
        dragTranslation = CGSize(width: proposed.width - panOffset.width, height: 0)
    }

    private func handleDragEnded(_ value: DragGesture.Value, size: CGSize) {
        if isZoomed {
            lastPanOffset = panOffset
            let boundarySwipeThreshold: CGFloat = 60
            if dragTranslation.width < -boundarySwipeThreshold {
                goToPage(currentIndex + 1)
            } else if dragTranslation.width > boundarySwipeThreshold {
                goToPage(currentIndex - 1)
            } else {
                withAnimation(.easeOut(duration: 0.2)) { dragTranslation = .zero }
            }
            return
        }

        let translation = value.translation
        guard abs(translation.width) > abs(translation.height) else {
            let dismissThreshold: CGFloat = 120
            if translation.height > dismissThreshold {
                dismiss()
            } else {
                withAnimation(.easeOut(duration: 0.2)) { dragTranslation = .zero }
            }
            return
        }

        let pageSwipeThreshold = size.width * 0.22
        if translation.width < -pageSwipeThreshold {
            goToPage(currentIndex + 1)
        } else if translation.width > pageSwipeThreshold {
            goToPage(currentIndex - 1)
        } else {
            withAnimation(.easeOut(duration: 0.2)) { dragTranslation = .zero }
        }
    }

    private func goToPage(_ index: Int) {
        guard messages.indices.contains(index) else {
            withAnimation(.easeOut(duration: 0.2)) { dragTranslation = .zero }
            return
        }
        withAnimation(.easeOut(duration: 0.25)) {
            currentIndex = index
            dragTranslation = .zero
            resetZoom()
        }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        panOffset = .zero
        lastPanOffset = .zero
    }
}

/// Decrypts and displays one page's media at an externally-controlled zoom
/// level — this view owns no gestures of its own; `MediaPagerView` is the
/// single owner of all touch handling so a zoom-pan gesture never has to
/// compete with a page-swipe gesture for the same drag.
private struct MediaPagerPage: View {
    let message: Message
    let conversationId: String
    let scale: CGFloat
    let panOffset: CGSize
    let onLoaded: (DecodedMedia?) -> Void

    @State private var media: DecodedMedia?
    @State private var failed = false

    var body: some View {
        Group {
            if let media {
                MediaImageView(media: media)
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(panOffset)
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "lock.slash")
                    Text("Can't decrypt this message")
                }
                .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: message.id) {
            let decrypted = await MediaDecryptor.decryptedMedia(for: message, conversationId: conversationId)
            media = decrypted
            failed = decrypted == nil
            onLoaded(decrypted)
        }
    }
}
