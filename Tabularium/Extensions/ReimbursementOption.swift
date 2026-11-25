import Foundation

/// Value-type helper (Extensions layer) that models how a transaction affects the
/// user's personal budget vs. what must be paid on the credit card statement:
/// - **`.personal`**: 100% of the charge counts toward the user's personal budget
///   and toward the card statement total.
/// - **`.pending`**: Paid with the user's card on behalf of someone else / another
///   budget and awaiting reimbursement (`⏳ Pending`). Counts `$0` toward the
///   personal budget, while still counting toward the card statement payment total.
/// - **`.reimbursed`**: Already paid back (`✓ Reimbursed`). Counts `$0` toward the
///   personal budget, while still included in the card statement payment total.
struct ReimbursementOption: Equatable {
    /// Stored status string on `Transaction.reimbursementStatus`.
    enum Status: String, CaseIterable, Equatable {
        case personal = "personal"       // 100% mine (default)
        case pending = "pending"         // 0% personal budget, awaiting reimbursement
        case reimbursed = "reimbursed"   // 0% personal budget, already reimbursed
    }

    var status: Status = .personal
    var note: String = ""

    init(status: Status = .personal, note: String = "") {
        self.status = status
        self.note = note
    }

    /// Initializes from the raw string stored on a Realm `Transaction`, normalizing
    /// any legacy `"excluded"` / `"split"` values into `.pending`.
    init(rawStatus: String, note: String) {
        switch rawStatus {
        case Status.pending.rawValue, "excluded", "split":
            self.status = .pending
        case Status.reimbursed.rawValue:
            self.status = .reimbursed
        default:
            self.status = .personal
        }
        self.note = note
    }

    /// True whenever this charge is reimbursable (`.pending` or `.reimbursed`).
    var isReimbursable: Bool {
        status != .personal
    }

    /// Flips `.pending` ↔ `.reimbursed` when the user clicks the pill badge directly
    /// on a dashboard row.
    var toggledStatus: Status {
        switch status {
        case .pending:    return .reimbursed
        case .reimbursed: return .pending
        case .personal:   return .personal
        }
    }

    /// How much of `periodCharge` (this billing cycle's installment or one-time charge)
    /// counts toward the user's personal budget and category chart.
    func budgetAmount(forPeriodCharge periodCharge: Double) -> Double {
        status == .personal ? periodCharge : 0
    }

    /// How much of `periodCharge` is excluded from the personal budget (reimbursable)
    /// while still owed on the card statement.
    func reimbursableAmount(forPeriodCharge periodCharge: Double) -> Double {
        status == .personal ? 0 : periodCharge
    }

    /// Compact pill badge shown on a transaction row in the dashboard (`nil` for normal
    /// personal charges).
    var badgeLabel: String? {
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch status {
        case .personal:
            return nil
        case .pending:
            return cleanNote.isEmpty ? "⏳ PENDING" : "⏳ \(cleanNote)"
        case .reimbursed:
            return cleanNote.isEmpty ? "✓ REIMBURSED" : "✓ \(cleanNote)"
        }
    }
}
