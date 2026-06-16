import Foundation
import RealmSwift   // Realm is the local database. `Object` and `@Persisted` come from here.

/// A payment card the user wants to track (e.g. "BBVA Platinum").
///
/// This is a **Model** — it only describes what gets stored in the database.
/// No logic, no UI. (See swift-standards.md → "Layer responsibilities".)
///
/// - `Object` makes this a Realm database row (a reference type / `class`).
/// - `Identifiable` gives it an `id`, which lets SwiftUI lists tell rows apart
///   (e.g. `ForEach(cards)` knows which card is which).
class Card: Object, Identifiable {
    // `@Persisted` = "store this property in the database".
    // `primaryKey: true` = this is the unique ID for the row; there can only be one.
    // `UUID().uuidString` generates a random unique string like "9F2A...-..." as the default.
    @Persisted(primaryKey: true) var id: String = UUID().uuidString

    @Persisted var name: String = ""        // display name, e.g. "BBVA Platinum"
    @Persisted var lastFour: String = ""     // last 4 digits, e.g. "1234"
    @Persisted var bank: String = ""         // issuing bank, e.g. "BBVA"
    @Persisted var type: String = "credit"   // "credit" or "debit"

    // The statement closing day of the month (1–31) — the "fecha de corte".
    // This lives PER CARD: one card might close on the 21st, another on the 3rd.
    //
    // The closing day is the FIRST day of the billing period, so a period runs from
    // the closing day of one month through the day BEFORE the next closing day, and
    // usually spans two calendar months. Example: close on 21 → period is the 21st
    // of one month through the 20th of the next (a charge on the 21st opens the new
    // period; the 20th is the last day of the previous one).
    //
    // `0` means "no closing day" (typical for debit cards), in which case the
    // dashboard falls back to whole calendar months.
    @Persisted var closingDay: Int = 0
}
