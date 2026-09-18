import SwiftUI
import UniformTypeIdentifiers

/// Picks an image or GIF from the Files app — iCloud Drive, "On My
/// iPhone," or any other file provider — via `UIDocumentPickerViewController`.
/// Distinct from `GalleryPickerView`'s `PHPickerViewController`, which only
/// reaches the Photos library, not arbitrary files.
struct FilesPickerView: UIViewControllerRepresentable {
    var onPick: (Data, MessageType) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // `.gif` already conforms to `.image`, so restricting to `.image`
        // alone still lets the user pick a GIF — it just also rules out
        // non-image files (PDFs, docs, etc.) from ever showing up.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FilesPickerView

        init(_ parent: FilesPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.onCancel()
                return
            }

            // Needed for files outside the app's own sandbox — iCloud
            // Drive or another file provider's documents, as opposed to
            // one already local to the device.
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                parent.onCancel()
                return
            }

            let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                ?? UTType(filenameExtension: url.pathExtension)
            let type: MessageType = contentType?.conforms(to: .gif) == true ? .gif : .image
            parent.onPick(data, type)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
