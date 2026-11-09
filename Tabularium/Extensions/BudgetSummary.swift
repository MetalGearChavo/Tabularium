import Foundation

/// Value type that computes the difference between a card's current period spending
/// (`spent`) and its target monthly/cycle budget (`budget`).
///
/// Kept free of SwiftUI/Realm so all budget math and daily-allowance calculations
/// are unit-tested in isolation (see `BudgetSummaryTests`).
struct BudgetSummary: Equatable {
    /// Visual threshold state for budget indicators.
    enum Status: Equatable {
        case under     // < 85% of budget
        case warning   // 85% ... 100% of budget
        case over      // > 100% of budget
    }

    static let warningThreshold: Double = 0.85

    let spent: Double
    let budget: Double

    /// `true` when the card has a positive monthly budget configured.
    var isConfigured: Bool { budget > 0 }

    /// Signed difference (`budget - spent`): positive means money remaining under
    /// budget; negative means how much the user is over budget.
    var difference: Double { budget - spent }

    /// Positive amount over budget (`0` when under or at budget).
    var overAmount: Double { max(0, spent - budget) }

    /// Ratio `spent / budget` clamped into `0...1` for proportional progress bars.
    var fraction: Double {
        guard budget > 0 else { return 0 }
        return min(max(spent / budget, 0), 1)
    }

    /// Whole-number percentage of budget spent (can exceed 100 when over budget).
    var percentage: Int {
        guard budget > 0 else { return 0 }
        return Int(((spent / budget) * 100).rounded())
    }

    /// Whether spending is comfortably under, approaching (≥85%), or over the budget.
    var status: Status {
        guard budget > 0 else { return .under }
        if spent > budget { return .over }
        if (spent / budget) >= Self.warningThreshold { return .warning }
        return .under
    }

    /// Human-readable diff badge text, e.g. `"+$5,800.00 left"` or `"-$1,200.00 over"`.
    var diffBadgeText: String {
        if difference >= 0 {
            return "+\(difference.currencyString) left"
        } else {
            return "-\(overAmount.currencyString) over"
        }
    }

    /// Number of days remaining in the visible period (including `now`), or `nil` if
    /// `now` does not fall inside `periodStart ..< periodEnd` (e.g. viewing a past month).
    func daysRemaining(
        now: Date = Date(),
        periodStart: Date,
        periodEnd: Date,
        calendar: Calendar = .current
    ) -> Int? {
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: periodStart)
        let end = calendar.startOfDay(for: periodEnd)
        guard today >= start && today < end else { return nil }
        let days = calendar.dateComponents([.day], from: today, to: end).day ?? 0
        return max(1, days)
    }

    /// How much the user can spend per remaining day in the current period without
    /// exceeding `budget` (`0` if already over budget, `nil` if not in the active period).
    func dailyAllowance(
        now: Date = Date(),
        periodStart: Date,
        periodEnd: Date,
        calendar: Calendar = .current
    ) -> Double? {
        guard isConfigured,
              let days = daysRemaining(now: now, periodStart: periodStart, periodEnd: periodEnd, calendar: calendar)
        else { return nil }
        return max(0, difference) / Double(days)
    }
}
