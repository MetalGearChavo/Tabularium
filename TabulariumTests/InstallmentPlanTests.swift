import Foundation
import Testing
@testable import Tabularium

/// Unit tests for `InstallmentPlan`: parsing `"6"` vs `"3/6"`, clamping bounds,
/// and back-dating the purchase date so a mid-stream MSI entry (e.g. `3/6` today)
/// lands on installment `3` in the selected period and back-fills `1/6` and `2/6`.
struct InstallmentPlanTests {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Clamping

    @Test func clampsOutOfRangeValues() {
        #expect(InstallmentPlan(current: 0, total: 0) == InstallmentPlan(current: 1, total: 1))
        #expect(InstallmentPlan(current: 9, total: 6) == InstallmentPlan(current: 6, total: 6))
        #expect(InstallmentPlan(current: -2, total: 120) == InstallmentPlan(current: 1, total: 99))
    }

    // MARK: - Smart string parsing ("6" or "3/6")

    @Test func parsesSingleNumberAsFirstInstallment() {
        #expect(InstallmentPlan.parse("6") == InstallmentPlan(current: 1, total: 6))
        #expect(InstallmentPlan.parse("1") == InstallmentPlan(current: 1, total: 1))
        #expect(InstallmentPlan.parse("") == InstallmentPlan(current: 1, total: 1))
    }

    @Test func parsesSlashNotationAsCurrentOverTotal() {
        #expect(InstallmentPlan.parse("3/6") == InstallmentPlan(current: 3, total: 6))
        #expect(InstallmentPlan.parse("03/12") == InstallmentPlan(current: 3, total: 12))
        // Trailing slash while the user is still typing ("3/") keeps 3 as current once total is typed,
        // or falls back safely if total is missing.
        #expect(InstallmentPlan.parse("3/") == InstallmentPlan(current: 1, total: 3))
    }

    // MARK: - Back-dating the purchase date

    @Test func firstInstallmentLeavesPurchaseDateUnchanged() {
        let selected = date(2026, 11, 7)
        let plan = InstallmentPlan(current: 1, total: 6)

        #expect(plan.effectivePurchaseDate(from: selected, calendar: utcCalendar) == selected)
    }

    @Test func midStreamInstallmentBackdatesPurchaseByCurrentMinusOneMonths() {
        // Entering 3/6 on Nov 7, 2026 means 1/6 was 2 months earlier: Sep 7, 2026.
        let selected = date(2026, 11, 7)
        let plan = InstallmentPlan(current: 3, total: 6)

        #expect(plan.effectivePurchaseDate(from: selected, calendar: utcCalendar) == date(2026, 9, 7))
    }

    @Test func backdatingCrossesYearBoundaryCleanly() {
        // Entering 3/6 on Feb 15, 2026 back-dates 2 months to Dec 15, 2025.
        let selected = date(2026, 2, 15)
        let plan = InstallmentPlan(current: 3, total: 6)

        #expect(plan.effectivePurchaseDate(from: selected, calendar: utcCalendar) == date(2025, 12, 15))
    }

    // MARK: - Amount calculation (new purchase vs. retroactive statement entry)

    @Test func newInstallmentPurchaseTreatsEnteredAmountAsTotal() {
        // Typing "6" with $3,000 means a $3,000 total purchase ($500/month).
        let plan = InstallmentPlan(current: 1, total: 6)

        #expect(plan.storedTotalAmount(fromEnteredAmount: 3000) == 3000)
        #expect(plan.monthlyAmount(fromEnteredAmount: 3000) == 500)
    }

    @Test func midStreamInstallmentTreatsEnteredAmountAsMonthlyPayment() {
        // Reading "3/6 $500" from a statement means $500 is THIS month's payment,
        // so the full purchase price stored in Realm must be $500 × 6 = $3,000.
        let plan = InstallmentPlan(current: 3, total: 6)

        #expect(plan.storedTotalAmount(fromEnteredAmount: 500) == 3000)
        #expect(plan.monthlyAmount(fromEnteredAmount: 500) == 500)
    }

    // MARK: - Editing an existing mid-stream MSI row (regression for 5/12 -> 9/12 bug)

    @Test func editingMidStreamRowUsesDisplayedDateAndPreservesInstallmentNumber() {
        // A 5/12 charge viewed on Nov 7, 2026 has storedPurchaseDate = Jul 7, 2026
        // and storedTotalAmount = 6000 ($500/month).
        // When opened in EditTransactionSheet, it must seed the form with the
        // displayed period's date (Nov 7), "5/12", and the monthly amount ("500.0"),
        // so re-saving "5/12" lands back on Jul 7 (5/12) instead of subtracting
        // another 4 months from Jul 7 (which caused the 9/12 bug).
        let storedPurchase = date(2026, 7, 7)
        let displayedInNov = date(2026, 11, 7)

        let seed = InstallmentPlan.editFormSeed(
            storedTotalAmount: 6000,
            totalInstallments: 12,
            storedPurchaseDate: storedPurchase,
            displayedRowDate: displayedInNov,
            installmentLabel: "5/12"
        )

        #expect(seed.date == displayedInNov)
        #expect(seed.monthsText == "5/12")
        #expect(Double(seed.amountText) == 500)

        // Now simulate the user saving that edit form at 5/12:
        let editedPlan = InstallmentPlan.parse(seed.monthsText)
        let savedPurchaseDate = editedPlan.effectivePurchaseDate(from: seed.date, calendar: utcCalendar)
        let savedTotal = editedPlan.storedTotalAmount(fromEnteredAmount: Double(seed.amountText)!)

        #expect(savedPurchaseDate == storedPurchase)
        #expect(savedTotal == 6000)
    }
}
