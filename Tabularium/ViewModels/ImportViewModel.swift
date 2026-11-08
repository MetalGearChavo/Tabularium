import Foundation
import Combine     // provides `ObservableObject` / the observation system

/// Coordinates the PDF import pipeline: extract text (`PDFService`) → parse and
/// categorize via the LLM (`LLMService`) → hand the results to `ReviewView` for
/// the user to confirm before anything is saved.
///
/// This is a **ViewModel**: it holds state and calls services, but never builds
/// UI. (swift-standards.md → "Architecture — MVVM".) `@MainActor` because it
/// publishes state the View reads, same reasoning as `DashboardViewModel`.
@MainActor
class ImportViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var parsedTransactions: [ParsedTransaction] = []
    @Published var errorMessage: String?
    @Published var sourceFileName = ""
    // "Parsing 3 of 6…" while chunked calls are in flight — empty otherwise.
    // Shown by the processing overlay so a multi-minute, multi-request import
    // doesn't look stuck.
    @Published var progressLabel = ""

    /// Runs the full pipeline for a dropped/picked PDF. On success,
    /// `parsedTransactions` is populated for the caller to present in review; on
    /// failure, `errorMessage` is set instead.
    ///
    /// Takes `[CategoryOption]` (a plain snapshot), not `[Category]` (Realm's
    /// live, thread-confined objects) — this function awaits a network call
    /// inside `LLMService`, and touching a live Realm object after an `await`
    /// resumes on a different thread crashes. The caller must snapshot
    /// categories *before* calling this. See `CategoryOption`.
    func process(fileURL: URL, categories: [CategoryOption]) async {
        sourceFileName = fileURL.lastPathComponent
        isProcessing = true
        errorMessage = nil
        parsedTransactions = []
        progressLabel = ""

        do {
            let rawText = try PDFService.extractText(from: fileURL)
            // Strip everything that isn't a plausible transaction line (see
            // `StatementTextFilter`) before it reaches the LLM — otherwise
            // marketing copy, legal notes, a loyalty-points ledger, and (for
            // BBVA) a CFDI annex full of base64 signature data can crowd out or
            // outright replace the real charges in a small local model's answer.
            let text = StatementTextFilter.keepLikelyTransactionLines(rawText)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "No lines with a currency amount were found in this PDF."
                isProcessing = false
                return
            }

            // One LLM call per statement stopped covering everything on a real
            // ~50-transaction statement — the model produced a complete, validly
            // shaped reply that simply stopped partway through instead of
            // continuing to the end (see CLAUDE.md notes). Splitting into
            // smaller batches (see `StatementChunker`) turns that into several
            // easier "track ~12 items" calls instead of one "track ~50" call.
            let chunks = StatementChunker.chunk(text)
            var allTransactions: [ParsedTransaction] = []
            var failedChunkCount = 0

            for (index, chunkText) in chunks.enumerated() {
                if Task.isCancelled { break }
                progressLabel = chunks.count > 1 ? "Parsing \(index + 1) of \(chunks.count)…" : ""
                do {
                    let transactions = try await LLMService.shared.parseStatement(text: chunkText, categories: categories)
                    allTransactions.append(contentsOf: transactions)
                } catch is CancellationError {
                    break
                } catch {
                    // One bad chunk (a decode failure, a timeout) shouldn't sink
                    // transactions the other chunks parsed fine.
                    failedChunkCount += 1
                }
            }

            if allTransactions.isEmpty {
                errorMessage = failedChunkCount > 0
                    ? "The LLM couldn't parse this statement (all \(failedChunkCount) part(s) failed)."
                    : "No transactions were found in this statement."
            } else {
                // Clean up recurring mangled merchant names ("DLO*UBER RIDES ;
                // Tarjeta Digital ***9171" → "Uber") and fill in a default
                // category, using rules the user has taught in Settings. No
                // `await` between this fetch and its use, so reading Realm
                // objects here directly (rather than needing a pre-snapshotted
                // parameter like `categories`) is safe — see swift-standards.md
                // → "Realm Conventions".
                let aliases = RealmService.shared.objects(MerchantAlias.self).map(MerchantAliasOption.init)
                parsedTransactions = MerchantAliasMatcher.apply(to: allTransactions, aliases: aliases)
            }
        } catch {
            // `LocalizedError` gives PDFService/LLMService's thrown errors a
            // friendly message; anything else falls back to a generic one.
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong reading this file."
        }

        progressLabel = ""
        isProcessing = false
    }

    /// Clears state so the next dropped file starts clean.
    func reset() {
        parsedTransactions = []
        errorMessage = nil
        sourceFileName = ""
        progressLabel = ""
    }
}
