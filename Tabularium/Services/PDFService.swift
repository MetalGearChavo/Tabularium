import Foundation
import PDFKit
import Vision   // Apple's on-device text-recognition framework — used only as an
                // OCR fallback below. This is a classical OCR engine, not an LLM:
                // no model download, no network call, ships with macOS.

/// Extracts raw text from a PDF bank statement so the LLM can parse it.
///
/// This is a **Service** — the lowest layer, talking to exactly one external
/// system (PDFKit, with a Vision OCR fallback). (swift-standards.md → "Services".)
///
/// Most bank e-statements are digitally generated PDFs with a real text layer,
/// so `PDFPage.string` reads them directly and instantly — this works for any
/// bank's layout since we hand the LLM raw text, not a fixed column format. Only
/// a scanned/photographed statement (no text layer) falls back to OCR.
enum PDFService {
    // Below this many characters, we treat a page's text layer as unreliable
    // (likely a scan) and OCR it instead of trusting the sparse/garbled text.
    private static let minCharsPerPage = 20

    /// Returns the combined text of every page in the PDF at `url`.
    static func extractText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw PDFServiceError.unreadablePDF
        }
        guard document.pageCount > 0 else {
            throw PDFServiceError.noExtractableText
        }

        var pages: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let layerText = page.string ?? ""
            if layerText.count >= minCharsPerPage {
                pages.append(layerText)
            } else {
                // No usable text layer on this page — likely a scan. OCR it instead.
                pages.append(try ocrText(for: page))
            }
        }

        let combined = pages.joined(separator: "\n")
        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PDFServiceError.noExtractableText
        }
        return combined
    }

    /// Renders a PDF page to an image and runs on-device OCR (Vision) on it.
    private static func ocrText(for page: PDFPage) throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        // Render at 2x so small statement fonts stay legible to OCR.
        let scale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        // `thumbnail(of:for:)` rasterizes the page into a correctly-oriented
        // `NSImage` — simpler and less error-prone than drawing into a CGContext
        // by hand, since PDFKit handles the coordinate flip internally.
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw PDFServiceError.noExtractableText
        }

        var recognizedLines: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            // `topCandidates(1)` asks Vision for just its single best guess per line.
            recognizedLines = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate
        // Statement text is usually Spanish (BBVA etc.); English covers the rest.
        request.recognitionLanguages = ["es-MX", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return recognizedLines.joined(separator: "\n")
    }
}

enum PDFServiceError: LocalizedError {
    case unreadablePDF
    case noExtractableText

    var errorDescription: String? {
        switch self {
        case .unreadablePDF:      return "Could not open this PDF."
        case .noExtractableText:  return "No text could be extracted from this PDF."
        }
    }
}
