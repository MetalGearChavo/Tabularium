import Foundation

/// A thread-safe snapshot of a `Category`'s fields.
///
/// Realm's `Category` objects are **thread-confined**: they may only be read on
/// the thread that fetched them, and must never be touched again after an
/// `await` resumes on a different thread — which `URLSession` calls (like
/// `LLMService`'s) are free to do. This plain `struct` copies out just the
/// fields the import pipeline needs, so it's safe to carry across `await`
/// boundaries and background threads, unlike the live Realm object.
struct CategoryOption: Identifiable {
    let id: String
    let name: String
    let emoji: String

    init(id: String, name: String, emoji: String = "") {
        self.id = id
        self.name = name
        self.emoji = emoji
    }

    init(_ category: Category) {
        self.init(id: category.id, name: category.name, emoji: category.emoji)
    }
}
