import Foundation

/// Applies user-taught `MerchantAlias` rules to freshly-parsed transactions,
/// cleaning up mangled merchant names and filling in a default category —
/// before the user even opens Review. See `MerchantAlias` for why this exists.
enum MerchantAliasMatcher {
    /// Rewrites every transaction whose description contains a known alias
    /// pattern (case-insensitive substring match). A transaction with no
    /// matching alias passes through unchanged. When an alias has no category
    /// (`categoryId == ""`), only the name is rewritten — whatever category the
    /// AI already assigned is left alone.
    static func apply(to transactions: [ParsedTransaction], aliases: [MerchantAliasOption]) -> [ParsedTransaction] {
        guard !aliases.isEmpty else { return transactions }

        return transactions.map { transaction in
            guard let alias = match(transaction.description, aliases: aliases) else { return transaction }
            var updated = transaction
            updated.description = alias.displayName
            if !alias.categoryId.isEmpty {
                updated.categoryId = alias.categoryId
            }
            return updated
        }
    }

    /// The first alias whose `pattern` case-insensitively appears anywhere in
    /// `description`, or `nil` if none match.
    private static func match(_ description: String, aliases: [MerchantAliasOption]) -> MerchantAliasOption? {
        let lowered = description.lowercased()
        return aliases.first { alias in
            !alias.pattern.isEmpty && lowered.contains(alias.pattern.lowercased())
        }
    }
}
