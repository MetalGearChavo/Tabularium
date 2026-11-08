import Foundation

/// Splits filtered statement text into smaller batches so each LLM call only
/// has to track a handful of transactions instead of an entire statement.
///
/// On a real ~50-transaction BBVA statement, a single call to `qwen2.5:7b`
/// covering the whole thing produced a complete, validly-shaped JSON reply —
/// but it silently stopped after ~25 items instead of continuing through the
/// rest (with a repeated entry right before it gave up, a classic sign of a
/// model losing its place). Splitting into smaller chunks turns "track ~50
/// items in order" into several much easier "track ~12 items" tasks.
enum StatementChunker {
    /// Small enough that a local model reliably covers every line in a chunk
    /// without dropping or repeating one; large enough to keep the number of
    /// LLM round-trips (and the fixed prompt overhead paid on each) reasonable.
    static let defaultChunkSize = 12

    static func chunk(_ text: String, linesPerChunk: Int = defaultChunkSize) -> [String] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }

        return stride(from: 0, to: lines.count, by: linesPerChunk).map { start in
            let end = min(start + linesPerChunk, lines.count)
            return lines[start..<end].joined(separator: "\n")
        }
    }
}
