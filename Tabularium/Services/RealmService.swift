import Foundation
import RealmSwift

/// The single place in the app that talks to the Realm database.
///
/// This is a **Service** — the lowest layer. Views and ViewModels call these
/// methods and never touch Realm directly. (swift-standards.md → "Services".)
class RealmService {
    // A "singleton": one shared instance for the whole app, reached via
    // `RealmService.shared`. `static let` means it's created once and never changes.
    static let shared = RealmService()

    // `private init` blocks other code from making its own `RealmService()`,
    // forcing everyone to use the shared instance above.
    //
    // It also registers the database's schema version. Whenever a `@Persisted`
    // property is added or removed, this number must go up by one, or Realm will
    // refuse to open an existing file ("migration required") and `try! Realm()`
    // below would crash. Adding/removing properties is an *additive* change, so we
    // don't need any migration code — Realm fills new columns with their default
    // (e.g. `Card.closingDay` → 0); bumping the version is enough, and existing
    // cards, categories and transactions are preserved.
    //
    // Schema history:
    //   v1 — added `Card.closingDay` (statement closing day / fecha de corte).
    //   v2 — added `Transaction.installments` (monthly installments / MSI).
    private init() {
        var config = Realm.Configuration.defaultConfiguration
        config.schemaVersion = 2
        Realm.Configuration.defaultConfiguration = config
    }

    // Opens a connection to the on-disk database file.
    // `try!` means "this can throw an error, but I'm sure it won't — crash if it does".
    // Fine for a personal app; production code would handle the error instead.
    private func open() -> Realm {
        try! Realm()
    }

    /// Inserts a new object into the database.
    /// All changes to Realm must happen inside a `write { }` block (a transaction).
    func save(_ object: Object) {
        let realm = open()
        try! realm.write {
            realm.add(object)
        }
    }

    /// Reads every object of a given type, e.g. `objects(Card.self)` → `[Card]`.
    ///
    /// `<T: Object>` is a generic: this one method works for any model type.
    /// `T.Type` / `Card.self` is how you pass a *type itself* as an argument.
    /// We copy into a plain `Array` so callers get a simple, detached list.
    func objects<T: Object>(_ type: T.Type) -> [T] {
        Array(open().objects(type))
    }

    /// Finds a single object by its primary key, or `nil` if none matches.
    /// The `?` in the return type `T?` means "might be nil".
    func object<T: Object>(_ type: T.Type, id: String) -> T? {
        open().object(ofType: type, forPrimaryKey: id)
    }

    /// Updates an existing object. You pass a closure that mutates the found object;
    /// we run it inside a write transaction so the changes are saved.
    /// Example: `update(Transaction.self, id: x) { $0.amount = 10 }`.
    func update<T: Object>(_ type: T.Type, id: String, _ changes: (T) -> Void) {
        let realm = open()
        // `guard let ... else { return }` is an early exit: if the object doesn't
        // exist, stop now instead of nesting the rest of the code in an `if`.
        guard let object = realm.object(ofType: type, forPrimaryKey: id) else { return }
        try! realm.write {
            changes(object)
        }
    }

    /// Deletes a single object by id.
    func delete<T: Object>(_ type: T.Type, id: String) {
        let realm = open()
        guard let object = realm.object(ofType: type, forPrimaryKey: id) else { return }
        try! realm.write {
            realm.delete(object)
        }
    }

    /// Deletes many objects at once, all inside a single write transaction.
    /// Used for cascade deletes — e.g. removing a card together with every
    /// transaction that belongs to it.
    func delete<T: Object>(_ objects: [T]) {
        guard !objects.isEmpty else { return }   // nothing to do; skip the write
        let realm = open()
        try! realm.write {
            realm.delete(objects)
        }
    }

    /// Wipes the entire database. Used by Settings → "Reset Onboarding".
    func deleteAll() {
        let realm = open()
        try! realm.write {
            realm.deleteAll()
        }
    }
}
