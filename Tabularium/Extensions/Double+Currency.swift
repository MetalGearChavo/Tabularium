import Foundation

// An "extension" adds new abilities to a type you don't own — here, the built-in
// `Double`. By convention the file is named `Type+Functionality.swift`.
// (swift-standards.md → "Extensions".)
extension Double {
    /// Formats this number as Mexican-peso currency, e.g. `1234.5` → "$1,234.50".
    ///
    /// `var` with only a getter is a "computed property": it runs code every time
    /// you read it instead of storing a value. So you can write `amount.currencyString`
    /// anywhere and get a formatted string back.
    var currencyString: String {
        // `.currency(code:)` picks the right symbol/grouping; `.narrow` uses the
        // short symbol ("$" rather than "MX$").
        formatted(.currency(code: "MXN").presentation(.narrow))
    }
}
