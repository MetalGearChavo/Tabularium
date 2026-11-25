import Foundation

/// Value-type helper (Extensions layer) that defines whether dashboard transactions
/// and daily ledger cards are ordered from most recent to oldest (`newestFirst`,
/// descending) or from earliest to most recent (`oldestFirst`, ascending).
enum TransactionSortOrder: String, CaseIterable, Identifiable, Hashable {
    case newestFirst = "newestFirst"
    case oldestFirst = "oldestFirst"

    var id: String { rawValue }

    /// Short label for compact toolbar buttons (`"Newest"` / `"Oldest"`).
    var shortLabel: String {
        switch self {
        case .newestFirst: return "Newest"
        case .oldestFirst: return "Oldest"
        }
    }

    /// Descriptive menu label (`"Newest first"` / `"Oldest first"`).
    var menuLabel: String {
        switch self {
        case .newestFirst: return "Newest first"
        case .oldestFirst: return "Oldest first"
        }
    }

    /// SF Symbol arrow indicating descending (`arrow.down`) vs. ascending (`arrow.up`).
    var iconName: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        }
    }

    /// Returns the opposite sort direction for single-click toggle controls.
    var toggled: TransactionSortOrder {
        self == .newestFirst ? .oldestFirst : .newestFirst
    }

    /// Sorts any collection of items by extracting a `Date` key from each element.
    func sort<T>(_ items: [T], by dateKey: (T) -> Date) -> [T] {
        items.sorted { lhs, rhs in
            let d1 = dateKey(lhs)
            let d2 = dateKey(rhs)
            switch self {
            case .newestFirst: return d1 > d2
            case .oldestFirst: return d1 < d2
            }
        }
    }
}
