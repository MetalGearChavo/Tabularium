import Foundation
import Testing
@testable import Tabularium

/// Tests for `MerchantAliasMatcher` — see CLAUDE.md → "Development Process".
struct MerchantAliasMatcherTests {
    private let aliases = [
        MerchantAliasOption(pattern: "UBER", displayName: "Uber", categoryId: "cat-transport"),
        MerchantAliasOption(pattern: "OXXO", displayName: "OXXO"),   // name-only, no category
    ]

    @Test func rewritesDescriptionAndCategoryOnMatch() {
        let tx = ParsedTransaction(date: Date(), description: "DLO*UBER RIDES ; Tarjeta Digital ***9171", amount: 142.33, categoryId: "")
        let result = MerchantAliasMatcher.apply(to: [tx], aliases: aliases)
        #expect(result.count == 1)
        #expect(result[0].description == "Uber")
        #expect(result[0].categoryId == "cat-transport")
    }

    @Test func matchIsCaseInsensitiveAndCatchesSingularOrPluralVariants() {
        // Real statement data prints both "UBER RIDE" and "UBER RIDES".
        let plural = ParsedTransaction(date: Date(), description: "dlo*uber rides", amount: 20, categoryId: "")
        let singular = ParsedTransaction(date: Date(), description: "DLO*UBER RIDE", amount: 20, categoryId: "")
        let result = MerchantAliasMatcher.apply(to: [plural, singular], aliases: aliases)
        #expect(result.allSatisfy { $0.description == "Uber" })
    }

    @Test func nameOnlyAliasLeavesExistingCategoryAlone() {
        // The "OXXO" alias has no categoryId — it should rewrite the name but
        // not touch whatever category the AI already assigned.
        let tx = ParsedTransaction(date: Date(), description: "OXXO GASOLINA SUR", amount: 850, categoryId: "cat-gas")
        let result = MerchantAliasMatcher.apply(to: [tx], aliases: aliases)
        #expect(result[0].description == "OXXO")
        #expect(result[0].categoryId == "cat-gas")
    }

    @Test func nonMatchingTransactionPassesThroughUnchanged() {
        let tx = ParsedTransaction(date: Date(), description: "SOME RANDOM MERCHANT", amount: 100, categoryId: "cat-misc")
        let result = MerchantAliasMatcher.apply(to: [tx], aliases: aliases)
        #expect(result[0].description == "SOME RANDOM MERCHANT")
        #expect(result[0].categoryId == "cat-misc")
    }

    @Test func emptyAliasListLeavesEverythingUnchanged() {
        let tx = ParsedTransaction(date: Date(), description: "UBER RIDES", amount: 100, categoryId: "")
        let result = MerchantAliasMatcher.apply(to: [tx], aliases: [])
        #expect(result[0].description == "UBER RIDES")
    }
}
