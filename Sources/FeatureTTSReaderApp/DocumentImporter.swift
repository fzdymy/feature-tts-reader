import SwiftUI
import UniformTypeIdentifiers

struct DocumentImporter: UIViewControllerRepresentable {
    var onImport: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImport: onImport) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = [UTType.plainText, UTType(filenameExtension: "txt")!]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onImport: (URL) -> Void
        init(onImport: @escaping (URL) -> Void) { self.onImport = onImport }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onImport(url)
        }
    }
}
