import Foundation

/// Strips a PDF-extracted statement down to lines that can plausibly be a real
/// transaction, before it's sent to the LLM.
///
/// A full bank statement is mostly noise once you're past the transaction table:
/// marketing copy, legal/interest disclosures, a loyalty-points ledger, and (for
/// BBVA specifically) a CFDI tax-invoice annex containing a multi-thousand-
/// character base64 signature blob. Sent whole, that noise both bloats the input
/// past what a small local model's context window handles well and gives it
/// something "clean-looking" to latch onto instead of the actual charges — this
/// is exactly what caused the AI to mirror a points table (`Generados`/
/// `Utilizados`/`Vencidos`) and later a CFDI block (`RFC`/`Régimen Fiscal`)
/// instead of returning real transactions, on a real BBVA statement.
///
/// A real charge line almost always carries a currency amount; the noise above
/// never does. Keeping only lines with a currency symbol is a simple, bank- and
/// language-agnostic filter — no BBVA-specific keywords, no assumptions about
/// column layout.
enum StatementTextFilter {
    private static let currencySymbols: Set<Character> = ["$", "€", "£"]

    static func keepLikelyTransactionLines(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .filter { line in line.contains { currencySymbols.contains($0) } }
            .joined(separator: "\n")
    }
}
