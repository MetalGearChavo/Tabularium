import Foundation
import Testing
@testable import Tabularium

/// Unit tests for `BudgetSummary`: per-card cycle budget diff math, status thresholds,
/// progress fraction, and daily allowance calculation across a billing period.
struct BudgetSummaryTests {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func underBudgetComputesPositiveRemainingAndUnderStatus() {
        let summary = BudgetSummary(spent: 14_200, budget: 20_000)

        #expect(summary.isConfigured == true)
        #expect(summary.difference == 5_800)
        #expect(summary.overAmount == 0)
        #expect(summary.percentage == 71)
        #expect(summary.fraction == 0.71)
        #expect(summary.status == .under)
    }

    @Test func nearLimitTriggersWarningStatusAt85Percent() {
        let summary = BudgetSummary(spent: 17_500, budget: 20_000)

        #expect(summary.difference == 2_500)
        #expect(summary.percentage == 88)
        #expect(summary.status == .warning)
    }

    @Test func overBudgetComputesNegativeDifferenceAndClampsBarFractionToOne() {
        let summary = BudgetSummary(spent: 21_200, budget: 20_000)

        #expect(summary.difference == -1_200)
        #expect(summary.overAmount == 1_200)
        #expect(summary.percentage == 106)
        #expect(summary.fraction == 1.0)
        #expect(summary.status == .over)
    }

    @Test func zeroBudgetMarksSummaryAsUnconfigured() {
        let summary = BudgetSummary(spent: 5_000, budget: 0)

        #expect(summary.isConfigured == false)
        #expect(summary.fraction == 0)
    }

    @Test func dailyAllowanceDividesRemainingBudgetByDaysLeftInActivePeriod() {
        // Period: Nov 1 ..< Dec 1 (exclusive). Today is Nov 21 -> 10 days left (Nov 21..30).
        let start = date(2026, 11, 1)
        let end = date(2026, 12, 1)
        let now = date(2026, 11, 21)
        let summary = BudgetSummary(spent: 14_200, budget: 20_000)

        let daysLeft = summary.daysRemaining(now: now, periodStart: start, periodEnd: end, calendar: utcCalendar)
        let perDay = summary.dailyAllowance(now: now, periodStart: start, periodEnd: end, calendar: utcCalendar)

        #expect(daysLeft == 10)
        #expect(perDay == 580)
    }

    @Test func pastOrFuturePeriodReturnsNilForDaysRemaining() {
        let start = date(2026, 10, 1)
        let end = date(2026, 11, 1)
        let now = date(2026, 11, 7)
        let summary = BudgetSummary(spent: 10_000, budget: 20_000)

        #expect(summary.daysRemaining(now: now, periodStart: start, periodEnd: end, calendar: utcCalendar) == nil)
        #expect(summary.dailyAllowance(now: now, periodStart: start, periodEnd: end, calendar: utcCalendar) == nil)
    }
}
