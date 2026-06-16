import Foundation
import RealmSwift

/// A single purchase/charge on a card — the core record of the whole app.
class Transaction: Object, Identifiable {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString

    // These two are "foreign keys": they hold the `id` of the related record
    // instead of pointing at the object directly. To find the parent statement
    // or card, you look up the row whose `id` matches.
    @Persisted var statementId: String = ""
    @Persisted var cardId: String = ""

    @Persisted var date: Date = Date()    // `Date()` defaults to "right now"
    @Persisted var amount: Double = 0.0   // money — `Double` is a decimal number

    // NOTE: named `transactionDescription`, not `description`.
    // Every Realm `Object` already has a built-in `description` property, so
    // reusing that name would clash. (swift-standards.md → "Realm Conventions".)
    @Persisted var transactionDescription: String = ""

    @Persisted var categoryId: String = ""  // which Category this belongs to (by id)
    @Persisted var reviewed: Bool = false   // has the user confirmed the AI's guess?

    // Number of monthly installments ("meses sin intereses" / MSI). `1` (or 0) means
    // a normal one-time charge. `N >= 2` means this purchase is split across N
    // billing cycles: `amount` is the FULL price, and each cycle is charged
    // `amount / installments`. The first installment (1/N) lands in the cycle of the
    // purchase `date`; each later cycle shows 2/N, 3/N, … The per-cycle occurrences
    // are computed on the fly (see DashboardViewModel) — we don't store N rows.
    @Persisted var installments: Int = 1
}
