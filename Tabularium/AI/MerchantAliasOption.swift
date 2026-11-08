import Foundation

/// A thread-safe snapshot of a `MerchantAlias`'s fields — same reasoning as
/// `CategoryOption` (see that file, and swift-standards.md → "Realm
/// Conventions"): Realm's managed objects are thread-confined and must never
/// cross an `await`, so anything used inside the async import pipeline goes
/// through a plain snapshot like this instead.
struct MerchantAliasOption {
    let pattern: String
    let displayName: String
    let categoryId: String

    init(pattern: String, displayName: String, categoryId: String = "") {
        self.pattern = pattern
        self.displayName = displayName
        self.categoryId = categoryId
    }

    init(_ alias: MerchantAlias) {
        self.init(pattern: alias.pattern, displayName: alias.displayName, categoryId: alias.categoryId)
    }
}
