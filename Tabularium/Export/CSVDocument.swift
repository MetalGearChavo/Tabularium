import SwiftUI
import UniformTypeIdentifiers

/// A tiny document wrapper so SwiftUI's `.fileExporter` can write a CSV string to a
/// user-chosen location. The system save panel handles the sandbox permission, so we
/// only need to hand over the bytes.
struct CSVDocument: FileDocument {
    // We produce (and could read) comma-separated text files.
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) { self.text = text }

    // Required by `FileDocument` for reading; we don't import via this path, but the
    // initializer must exist.
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            text = ""
        }
    }

    // Called when the user confirms the save panel: turn our string into file bytes.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
