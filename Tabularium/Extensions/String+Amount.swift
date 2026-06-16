import Foundation

// Adds amount-field helpers to `String`. (swift-standards.md → "Extensions".)
extension String {
    /// Keeps only digits and a single decimal point, dropping everything else.
    ///
    /// Used to live-filter the AMOUNT text field as the user types, so the value is
    /// always something `Double(_:)` can parse. This sidesteps locale headaches:
    /// `Double("1,234.56")` is `nil`, but by never letting a comma (or letters, or a
    /// second dot) into the field, what's left is always a clean "1234.56".
    var amountInputFiltered: String {
        var result = ""
        var hasDot = false
        for character in self {
            if character.isNumber {
                result.append(character)
            } else if character == "." && !hasDot {
                // Allow the first dot only; ignore any further ones.
                result.append(character)
                hasDot = true
            }
            // Anything else (letters, commas, spaces, "$", extra dots) is dropped.
        }
        return result
    }
}
