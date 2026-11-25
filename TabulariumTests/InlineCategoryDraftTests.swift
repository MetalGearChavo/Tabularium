import Foundation
import Testing
@testable import Tabularium

/// Unit tests for `InlineCategoryDraft`: validating and sanitizing the inline
/// "+ Add category" row inside `CategoryDropdownPicker` (emoji filtering to a
/// single emoji, trimming whitespace from the name, and formatting the selected
/// category button label).
struct InlineCategoryDraftTests {

    @Test func sanitizesEmojiToSingleLastPickedEmoji() {
        // Non-emoji characters are stripped; when multiple emojis are typed or
        // picked in sequence, only the most recent one is kept so the emoji box
        // always holds at most one symbol.
        #expect(InlineCategoryDraft.sanitizeEmoji("abc") == "")
        #expect(InlineCategoryDraft.sanitizeEmoji("🍔") == "🍔")
        #expect(InlineCategoryDraft.sanitizeEmoji("🍔🚗") == "🚗")
        #expect(InlineCategoryDraft.sanitizeEmoji("a🛒b") == "🛒")
    }

    @Test func draftRequiresNonBlankNameToBeValid() {
        #expect(InlineCategoryDraft(emoji: "🍔", name: "").isValid == false)
        #expect(InlineCategoryDraft(emoji: "🍔", name: "   ").isValid == false)
        #expect(InlineCategoryDraft(emoji: "", name: "Food").isValid == true)
        #expect(InlineCategoryDraft(emoji: "🍔", name: "  Food  ").trimmedName == "Food")
        #expect(InlineCategoryDraft(emoji: " 🍔 ", name: "Food").trimmedEmoji == "🍔")
    }

    @Test func formatsCategoryLabelCleanlyWithOrWithoutEmoji() {
        #expect(InlineCategoryDraft.displayLabel(emoji: "🍔", name: "Food") == "🍔 Food")
        #expect(InlineCategoryDraft.displayLabel(emoji: "", name: "Food") == "Food")
    }
}
