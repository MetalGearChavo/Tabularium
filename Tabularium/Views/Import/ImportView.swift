import SwiftUI

/// Placeholder for the PDF import screen.
///
/// Not wired into navigation yet — importing currently happens by dragging a PDF
/// onto the dashboard. This will become the dedicated import + review flow later
/// (PDFKit extracts text → Ollama parses it → user reviews before saving).
struct ImportView: View {
    var body: some View {
        Text("Import")
            .font(.largeTitle)
            // Expand to fill the window and center the text.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ImportView()
}
