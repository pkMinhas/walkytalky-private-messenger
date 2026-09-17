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

    @State private var uiImage: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            Group {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
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
            uiImage = await MediaDecryptor.decryptedImage(for: message, conversationId: conversationId)
            failed = uiImage == nil
        }
    }
}

/// Paged fullscreen media viewer: swipe left/right (or drag) to move
/// between every media message in the conversation, starting at
/// `startIndex`. Each page keeps the existing pinch-zoom/pan/share
/// behavior from `FullscreenImageViewer`.
struct MediaPagerView: View {
    let messages: [Message]
    let conversationId: String
    let startIndex: Int

    @State private var currentIndex: Int

    init(messages: [Message], conversationId: String, startIndex: Int) {
        self.messages = messages
        self.conversationId = conversationId
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                MediaPagerPage(
                    message: message,
                    conversationId: conversationId,
                    pageInfo: messages.count > 1 ? "\(index + 1) of \(messages.count)" : nil
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
    }
}

private struct MediaPagerPage: View {
    let message: Message
    let conversationId: String
    let pageInfo: String?

    @State private var uiImage: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let uiImage {
                FullscreenImageViewer(image: uiImage, pageInfo: pageInfo)
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    if failed {
                        VStack(spacing: 8) {
                            Image(systemName: "lock.slash")
                            Text("Can't decrypt this message")
                        }
                        .foregroundStyle(.white)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            }
        }
        .task(id: message.id) {
            uiImage = await MediaDecryptor.decryptedImage(for: message, conversationId: conversationId)
            failed = uiImage == nil
        }
    }
}
