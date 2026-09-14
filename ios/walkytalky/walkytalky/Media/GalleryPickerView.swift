import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Picks an existing photo or GIF from the library via `PHPickerViewController`
/// — the modern, privacy-preserving picker that runs out-of-process, so it
/// needs no `NSPhotoLibraryUsageDescription`.
struct GalleryPickerView: UIViewControllerRepresentable {
    var onPick: (Data, MessageType) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: GalleryPickerView

        init(_ parent: GalleryPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.onCancel()
                return
            }

            let gifType = UTType.gif.identifier
            if provider.hasItemConformingToTypeIdentifier(gifType) {
                provider.loadDataRepresentation(forTypeIdentifier: gifType) { [parent] data, _ in
                    DispatchQueue.main.async {
                        if let data {
                            parent.onPick(data, .gif)
                        } else {
                            parent.onCancel()
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [parent] object, _ in
                    DispatchQueue.main.async {
                        if let image = object as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                            parent.onPick(data, .image)
                        } else {
                            parent.onCancel()
                        }
                    }
                }
            } else {
                parent.onCancel()
            }
        }
    }
}
