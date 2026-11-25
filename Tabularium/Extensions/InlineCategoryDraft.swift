import Foundation

/// Value-type helper (Extensions layer) that backs the inline "+ Add category" row
/// inside `CategoryDropdownPicker`.
///
/// Keeping the validation, emoji sanitization, and label formatting in a pure `struct`
/// (instead of burying it inside the SwiftUI view) lets us unit-test the rules without
/// needing to render the UI or touch Realm.
struct InlineCategoryDraft: Equatable {
    var emoji: String = ""
    var name: String = ""

    /// The category name with leading/trailing spaces stripped.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The emoji string with leading/trailing spaces stripped.
    var trimmedEmoji: String {
        emoji.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A new category only requires a non-blank name (emoji is optional).
    var isValid: Bool {
        !trimmedName.isEmpty
    }

    /// Filters a raw text-field string down to at most one emoji — keeping the
    /// *last* emoji picked so choosing a new one in the macOS character palette
    /// replaces the previous emoji cleanly.
    static func sanitizeEmoji(_ raw: String) -> String {
        // `filter { $0.isEmoji }` walks each `Character` and keeps only emojis
        // (using `Character.isEmoji` from `Character+Emoji.swift`).
        let emojisOnly = raw.filter { $0.isEmoji }
        // `.last.map(String.init)` converts the final `Character` back into a
        // `String`, or falls back to `""` via `??` (nil-coalescing) if none remain.
        return emojisOnly.last.map(String.init) ?? ""
    }

    /// Formats a category's emoji and name for display in the dropdown button and
    /// menu rows, omitting the leading space when a category has no emoji.
    static func displayLabel(emoji: String, name: String) -> String {
        let cleanEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanEmoji.isEmpty ? name : "\(cleanEmoji) \(name)"
    }
}
