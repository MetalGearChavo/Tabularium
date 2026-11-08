import Foundation

/// One transaction as parsed (and categorized) by the LLM from a statement, before
/// the user has reviewed it and before it becomes a real Realm `Transaction`.
///
/// A plain `struct` (a value type — copied, not shared) on purpose: it's a working
/// draft `ReviewView` edits locally, not a database record. Nothing is written to
/// Realm until the user taps "Save All". `var` fields (not `let`) because the
/// review screen binds directly to them for in-place editing.
struct ParsedTransaction: Identifiable {
    let id: String = UUID().uuidString   // for SwiftUI's ForEach/List, not persisted

    var date: Date
    var description: String
    var amount: Double
    var categoryId: String   // resolved from the AI's category name; "" if unmatched
}
