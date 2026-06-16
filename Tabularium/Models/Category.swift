import Foundation
import RealmSwift

/// A user-defined spending category (e.g. "🍔 Food", "⛽ Gas").
///
/// Categories are created during onboarding and shared across all cards.
/// Each `Transaction` points at one category by storing its `id` in `categoryId`.
class Category: Object, Identifiable {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var name: String = ""    // e.g. "Groceries"
    @Persisted var emoji: String = ""   // e.g. "🛒" — shown in the dashboard rows
}
