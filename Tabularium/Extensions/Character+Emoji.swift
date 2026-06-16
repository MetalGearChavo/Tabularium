import Foundation

// An "extension" adds new abilities to a type you don't own — here, the built-in
// `Character`. (swift-standards.md → "Extensions".)
extension Character {
    /// True when this character is an emoji (e.g. "🛒", "👨‍👩‍👧").
    ///
    /// Swift has no built-in `isEmoji`, so we inspect the character's Unicode
    /// scalars. A `Character` can be made of several scalars (e.g. a flag or a
    /// "family" emoji joined by zero-width joiners), which is why we check both
    /// the single-scalar and multi-scalar cases.
    var isEmoji: Bool {
        // `unicodeScalars` is the list of Unicode code points making up this character.
        guard let first = unicodeScalars.first else { return false }

        // A single scalar above U+238C is a "real" emoji. The cutoff matters because
        // plain digits/`#`/`*` ALSO report `isEmoji == true` (they have emoji
        // *presentations* like 1️⃣), and we don't want to accept a bare "1" as an emoji.
        let isSingleEmoji = unicodeScalars.count == 1 && first.properties.isEmoji && first.value > 0x238C

        // Anything built from multiple scalars whose first scalar is an emoji is a
        // combined/sequence emoji (flags, skin-tone variants, ZWJ sequences, …).
        let isCombinedEmoji = unicodeScalars.count > 1 && first.properties.isEmoji

        return isSingleEmoji || isCombinedEmoji
    }
}
