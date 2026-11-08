import Testing
@testable import Tabularium

/// Tests for `StatementTextFilter` — see CLAUDE.md → "Development Process"
/// (spec-driven: written before `StatementTextFilter` existed).
struct StatementTextFilterTests {

    @Test func keepsLinesWithACurrencyAmount() {
        let input = "18-jul-2026 20-jul-2026 BK EL CAZADERO + $374.00"
        let result = StatementTextFilter.keepLikelyTransactionLines(input)
        #expect(result == input)
    }

    @Test func dropsLinesWithNoCurrencySymbol() {
        // A loyalty-points ledger row: dates and comma-grouped numbers, but no
        // currency symbol — this is exactly what caused the AI to hallucinate a
        // "puntos" schema instead of real transactions (see CLAUDE.md notes).
        let input = "32,644 4,777 34,748 30 2,643 0"
        let result = StatementTextFilter.keepLikelyTransactionLines(input)
        #expect(result.isEmpty)
    }

    @Test func dropsProseAndKeepsTransactionsInAMixedStatement() {
        let input = """
        Descubre todo lo que tu TDC puede hacer por ti
        03-jun-2026 OXXO GASOLINA SUR + $850.00
        Régimen Fiscal: 616 - Sin obligaciones fiscales
        04-jun-2026 UBER EATS MX + $210.50
        """
        let result = StatementTextFilter.keepLikelyTransactionLines(input)
        #expect(result == "03-jun-2026 OXXO GASOLINA SUR + $850.00\n04-jun-2026 UBER EATS MX + $210.50")
    }

    @Test func supportsEuroAndPoundSymbolsToo() {
        let input = "10-jun-2026 CAFE PARIS €12.50\n10-jun-2026 TESCO £8.00\nNo amount here at all"
        let result = StatementTextFilter.keepLikelyTransactionLines(input)
        #expect(result == "10-jun-2026 CAFE PARIS €12.50\n10-jun-2026 TESCO £8.00")
    }

    @Test func emptyInputProducesEmptyOutput() {
        #expect(StatementTextFilter.keepLikelyTransactionLines("").isEmpty)
    }
}
