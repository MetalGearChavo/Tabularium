import Foundation
import Testing
@testable import Tabularium

/// Unit tests for `ReimbursementOption` (Option 2 — Reimbursement Status Tracker):
/// - `.personal`: counts 100% toward the user's personal budget and card statement total.
/// - `.pending`: counts $0 toward the user's personal budget, 100% toward the card
///   statement total and `pendingTotal`, and renders an orange `⏳` badge.
/// - `.reimbursed`: counts $0 toward the user's personal budget, 100% toward the card
///   statement total and `reimbursedTotal`, and renders a green `✓` badge.
struct ReimbursementOptionTests {

    @Test func personalTransactionCountsFullAmountTowardBudget() {
        let opt = ReimbursementOption(status: .personal, note: "")

        #expect(opt.budgetAmount(forPeriodCharge: 1500) == 1500)
        #expect(opt.reimbursableAmount(forPeriodCharge: 1500) == 0)
        #expect(opt.badgeLabel == nil)
    }

    @Test func pendingAndReimbursedExcludeFromPersonalBudgetButStayOnCardStatement() {
        let pending = ReimbursementOption(status: .pending, note: "Viaje")
        #expect(pending.budgetAmount(forPeriodCharge: 4500) == 0)
        #expect(pending.reimbursableAmount(forPeriodCharge: 4500) == 4500)
        #expect(pending.badgeLabel == "⏳ Viaje")
        #expect(pending.toggledStatus == .reimbursed)

        let pendingNoNote = ReimbursementOption(status: .pending, note: "   ")
        #expect(pendingNoNote.badgeLabel == "⏳ PENDING")

        let reimbursed = ReimbursementOption(status: .reimbursed, note: "Trabajo")
        #expect(reimbursed.budgetAmount(forPeriodCharge: 4500) == 0)
        #expect(reimbursed.reimbursableAmount(forPeriodCharge: 4500) == 4500)
        #expect(reimbursed.badgeLabel == "✓ Trabajo")
        #expect(reimbursed.toggledStatus == .pending)

        let reimbursedNoNote = ReimbursementOption(status: .reimbursed, note: "")
        #expect(reimbursedNoNote.badgeLabel == "✓ REIMBURSED")
    }

    @Test func legacyExcludedOrSplitStatusNormalizesToPending() {
        let legacy = ReimbursementOption(rawStatus: "excluded", note: "Amigos")
        #expect(legacy.status == .pending)
        #expect(legacy.budgetAmount(forPeriodCharge: 2000) == 0)
        #expect(legacy.badgeLabel == "⏳ Amigos")
    }
}
