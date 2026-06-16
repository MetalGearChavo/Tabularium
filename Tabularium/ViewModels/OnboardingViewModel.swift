import Foundation
import Combine
import SwiftUI

/// Drives the first-launch setup wizard: choose how many cards, enter each card's
/// details, define categories, then save everything to the database.
@MainActor
class OnboardingViewModel: ObservableObject {

    /// Which screen of the wizard we're on. An `enum` is a fixed set of named cases —
    /// the `step` can only ever be one of these, which makes invalid states impossible.
    enum Step {
        case welcome
        case cardCount
        case cardDetails(index: Int)  // a case can carry data: which card we're editing
        case categories
        case complete
    }

    /// A work-in-progress card the user is typing, before it's saved to the database.
    /// It's a `struct` (temporary value), separate from the `Card` Realm model.
    struct CardDraft {
        var name: String = ""
        var lastFour: String = ""
        var bank: String = ""
        var type: String = "credit"
        var closingDay: String = ""   // "fecha de corte" day (1–31); optional, blank = none

        /// Computed each time: is this card complete and valid to save?
        var isValid: Bool {
            // `allSatisfy(\.isNumber)` checks every character is a digit.
            // `\.isNumber` is a "key path" — shorthand for `{ $0.isNumber }`.
            // The closing day is optional, so it isn't part of validity.
            !name.isEmpty && lastFour.count == 4 && lastFour.allSatisfy(\.isNumber) && !bank.isEmpty
        }
    }

    /// A work-in-progress category the user is typing.
    struct CategoryDraft {
        var name: String = ""
        var emoji: String = ""

        var isValid: Bool { !name.isEmpty }
    }

    @Published var step: Step = .welcome
    @Published var cardCount: Int = 1
    @Published var cards: [CardDraft] = [CardDraft()]              // starts with one blank draft
    @Published var categories: [CategoryDraft] = [CategoryDraft()]

    /// After the user picks a count, create that many blank card drafts and move on.
    func applyCardCount() {
        // `(0..<cardCount).map { ... }` makes `cardCount` blank drafts.
        // The `_` means "I don't care about the loop value, just repeat".
        cards = (0..<cardCount).map { _ in CardDraft() }
        step = .cardDetails(index: 0)
    }

    /// After finishing one card, go to the next card — or to categories if done.
    func nextCardOrCategories(currentIndex: Int) {
        let nextIndex = currentIndex + 1
        if nextIndex < cardCount {
            step = .cardDetails(index: nextIndex)
        } else {
            step = .categories
        }
    }

    func addCategory() {
        categories.append(CategoryDraft())
    }

    /// Removes categories at the given list positions (SwiftUI passes an `IndexSet`).
    func removeCategory(at offsets: IndexSet) {
        categories.remove(atOffsets: offsets)
    }

    /// Final step: turn every draft into a real database record and mark onboarding done.
    func complete() {
        let service = RealmService.shared

        for draft in cards {
            let card = Card()       // a fresh empty Realm object
            card.name = draft.name  // copy the typed values onto it
            card.lastFour = draft.lastFour
            card.bank = draft.bank
            card.type = draft.type
            // Store the corte only when it's a valid 1–31; blank stays 0 ("none").
            if let day = Int(draft.closingDay), (1...31).contains(day) {
                card.closingDay = day
            }
            service.save(card)
        }

        // `where draft.isValid` filters the loop: skip any blank/invalid category.
        for draft in categories where draft.isValid {
            let category = Category()
            category.name = draft.name
            category.emoji = draft.emoji
            service.save(category)
        }

        // `UserDefaults` is tiny key/value storage for simple settings/flags.
        // This flag is what `ContentView` checks to skip onboarding next launch.
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        step = .complete
    }
}
