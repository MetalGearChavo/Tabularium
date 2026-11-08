import Foundation
import Testing
@testable import Tabularium

/// Tests for `LLMService.parse` against real deviations captured from actual
/// local-model output (see CLAUDE.md → "Development Process" — written before
/// the parser tolerated any of this, against a real `qwen2.5:7b` response saved
/// during import debugging).
struct LLMResponseParsingTests {
    private let categories = [CategoryOption(id: "cat-transport", name: "Transporte")]

    @Test func fallsBackToDateRangeStartDateWhenDateKeyIsMissing() throws {
        // qwen2.5:7b, given a BBVA statement with two dates per row (purchase +
        // posting date), kept inventing a "date_range" object instead of a
        // single "date" string despite explicit prompt instructions not to.
        let content = """
        {"transactions":[
            {"date_range":{"start_date":"18-jul-2026","end_date":"20-jul-2026"},"description":"UBER","amount":142.33,"category":"Transporte"}
        ]}
        """
        let result = try LLMService.shared.parse(content: content, categories: categories)
        #expect(result.count == 1)
        #expect(result.first?.description == "UBER")
        #expect(result.first?.categoryId == "cat-transport")

        let date = try #require(result.first?.date)
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        #expect(comps.year == 2026)
        #expect(comps.month == 7)
        #expect(comps.day == 18)
    }

    @Test func dropsTransactionsWithNonPositiveAmounts() throws {
        // A payment/credit TO the card the model included despite being told to
        // skip it — recognizable by a non-positive amount even when the model
        // doesn't flag it any other way (it also invented its own "type" field
        // here instead of "category", which the next test covers separately).
        let content = """
        {"transactions":[
            {"date":"2026-07-18","description":"SU PAGO INTERBANCARIO","amount":-7800.00,"category":""},
            {"date":"2026-07-18","description":"UBER","amount":142.33,"category":"Transporte"}
        ]}
        """
        let result = try LLMService.shared.parse(content: content, categories: categories)
        #expect(result.count == 1)
        #expect(result.first?.description == "UBER")
    }

    @Test func categoryDefaultsToEmptyWhenKeyIsMissing() throws {
        let content = """
        {"transactions":[
            {"date":"2026-07-18","description":"UBER","amount":142.33,"type":"cargo"}
        ]}
        """
        let result = try LLMService.shared.parse(content: content, categories: categories)
        #expect(result.first?.categoryId == "")
    }

    @Test func dropsItemsWhoseDateCantBeParsedAtAllInsteadOfGuessingToday() throws {
        let content = """
        {"transactions":[
            {"date":"not a date","description":"???","amount":10.00,"category":""},
            {"date":"2026-07-18","description":"UBER","amount":142.33,"category":"Transporte"}
        ]}
        """
        let result = try LLMService.shared.parse(content: content, categories: categories)
        #expect(result.count == 1)
        #expect(result.first?.description == "UBER")
    }

    @Test func stillParsesTheDocumentedISOShape() throws {
        let content = """
        {"transactions":[{"date":"2026-06-03","description":"OXXO","amount":850.00,"category":"Transporte"}]}
        """
        let result = try LLMService.shared.parse(content: content, categories: categories)
        #expect(result.count == 1)
        #expect(result.first?.categoryId == "cat-transport")
    }

    @Test func fallsBackToCamelCaseDateRangeKeys() throws {
        // A different real response used "dateRange"/"startDate"/"endDate"
        // (camelCase) instead of the snake_case shape handled above — same
        // invented structure, different casing.
        let content = """
        {"transactions":[
            {"dateRange":{"startDate":"18-jul-2026","endDate":"20-jul-2026"},"description":"UBER","amount":142.33}
        ]}
        """
        let result = try LLMService.shared.parse(content: content, categories: categories)
        #expect(result.count == 1)
        #expect(result.first?.description == "UBER")
    }

    @Test func salvagesCompleteTransactionsFromATruncatedResponse() throws {
        // Real capture: a long BBVA statement pushed the model's reply past
        // `maxTokens`, so the JSON got cut off mid-object at the end. The whole
        // document is invalid JSON as a result, but everything before the
        // cutoff is individually well-formed — recover that instead of losing
        // every transaction over one incomplete trailing item.
        let content = """
        {
          "transactions": [
            {"date":"2026-07-18","description":"TOTAL PLAY CR","amount":550.00,"category":"Transporte"},
            {"date":"2026-07-19","description":"UBER RIDES","amount":142.33,"category":"Transporte"},
            {
              "dateRange": {"startDate": "17-ago-2026", "endDate": "18-ago-2026"}
        """
        let result = try LLMService.shared.parse(content: content, categories: categories)
        #expect(result.count == 2)
        #expect(result.map(\.description) == ["TOTAL PLAY CR", "UBER RIDES"])
    }
}
