import Foundation
import RealmSwift

/// A user-taught rule: "when a transaction description contains `pattern`,
/// show it as `displayName` and file it under `categoryId`."
///
/// Bank statements print merchant names mangled by whatever payment processor
/// touched the charge — `"DLO*UBER RIDES ; Tarjeta Digital ***9171"`,
/// `"SQ *WEST S HAYWARD DAIRY"`, `"MERPAGO*RAMIROSANCHEZ"`. The AI re-guesses
/// these fresh on every import and doesn't always agree with itself. This model
/// lets the user fix a recurring one ONCE, in Settings, and have it applied
/// automatically on every import after that (`MerchantAliasMatcher`).
///
/// This is a **Model** — a Realm database row, no logic. (swift-standards.md →
/// "Layer responsibilities".)
class MerchantAlias: Object, Identifiable {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString

    // Matched case-insensitively as a substring against a transaction's raw
    // description — e.g. "UBER" matches both "DLO*UBER RIDES ..." and
    // "DLO*UBER RIDE ..." (real statements print both singular and plural).
    @Persisted var pattern: String = ""

    @Persisted var displayName: String = ""   // e.g. "Uber"
    // "" = don't force a category, just clean up the name.
    @Persisted var categoryId: String = ""
}
