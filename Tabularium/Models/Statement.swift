import Foundation
import RealmSwift

/// One imported bank statement (a billing period for a card), containing many
/// transactions. Currently created by the import flow.
class Statement: Object, Identifiable {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var cardId: String = ""        // which card this statement belongs to
    @Persisted var periodStart: Date = Date() // billing period start
    @Persisted var periodEnd: Date = Date()   // billing period end
    @Persisted var importedAt: Date = Date()  // when we imported it

    // `List` is Realm's version of an array for stored objects. A statement
    // "owns" its transactions, so they live inside this list.
    @Persisted var transactions: List<Transaction>
}
