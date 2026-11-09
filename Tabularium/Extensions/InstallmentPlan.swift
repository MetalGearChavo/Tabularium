import Foundation

/// Value type representing a monthly-installment (MSI) schedule during transaction
/// entry: which installment the user is currently on (`current`, 1-based) out of
/// `total` monthly payments.
///
/// Used by `AddTransactionSheet` to let the user enter an in-progress MSI (e.g. `3/6`)
/// on the currently selected date without manually scrolling the calendar back in time.
/// On save, `effectivePurchaseDate(from:calendar:)` shifts the stored purchase date
/// back by `-(current - 1)` months so the current period displays `current/total`
/// and past periods (`1/total ..< current/total`) are back-filled automatically.
struct InstallmentPlan: Equatable {
    let current: Int
    let total: Int

    /// Creates a valid plan, clamping `total` into `1...99` and `current` into `1...total`.
    init(current: Int = 1, total: Int = 1) {
        let clampedTotal = Swift.min(Swift.max(total, 1), 99)
        let clampedCurrent = Swift.min(Swift.max(current, 1), clampedTotal)
        self.total = clampedTotal
        self.current = clampedCurrent
    }

    /// Parses either a plain count (`"6"` → `1/6`) or slash notation (`"3/6"` → `3/6`).
    /// If the string after `/` is still empty (e.g. the user just typed `"3/"`), it
    /// treats the first number as `total` (`1/3`) until the second number is entered.
    static func parse(_ raw: String) -> InstallmentPlan {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count >= 2 {
            let first = Int(parts[0].filter(\.isNumber)) ?? 1
            let secondDigits = parts[1].filter(\.isNumber)
            if let second = Int(secondDigits), !secondDigits.isEmpty {
                return InstallmentPlan(current: first, total: second)
            } else {
                return InstallmentPlan(current: 1, total: first)
            }
        }
        let single = Int(trimmed.filter(\.isNumber)) ?? 1
        return InstallmentPlan(current: 1, total: single)
    }

    /// Filters a raw keystroke string for the smart `"3/6"` text field (Proposal B):
    /// allows at most two digits, an optional `/`, and at most two digits after it.
    static func filterSmartInput(_ raw: String) -> String {
        var result = ""
        var seenSlash = false
        var digitsInSegment = 0

        for char in raw {
            if char.isNumber {
                if digitsInSegment < 2 {
                    result.append(char)
                    digitsInSegment += 1
                }
            } else if char == "/" && !seenSlash && !result.isEmpty {
                result.append("/")
                seenSlash = true
                digitsInSegment = 0
            }
        }
        return result
    }

    /// Formats the plan for the smart `"3/6"` field: `"6"` when starting at `1/6`,
    /// or `"3/6"` when starting mid-stream (`current > 1`).
    var smartString: String {
        current > 1 ? "\(current)/\(total)" : "\(total)"
    }

    /// Shifts `selectedDate` back by `-(current - 1)` months when `current >= 2` and
    /// `total >= 2`, so that `selectedDate` lands on installment `current/total`.
    func effectivePurchaseDate(from selectedDate: Date, calendar: Calendar = .current) -> Date {
        guard total >= 2, current >= 2 else { return selectedDate }
        return calendar.date(byAdding: .month, value: -(current - 1), to: selectedDate) ?? selectedDate
    }

    /// Converts the number typed in the `AMOUNT` field into the full purchase price
    /// stored in `Transaction.amount`.
    ///
    /// - When entering a new purchase (`current == 1`, e.g. `"6"`), the user enters
    ///   the full purchase price (`$3,000`), which is stored as-is.
    /// - When entering a backtracked / mid-stream charge off a statement (`current >= 2`,
    ///   e.g. `"3/6"`), the statement shows **this month's payment** (`$500`), so the
    ///   stored total is `enteredAmount * total` (`$500 × 6 = $3,000`).
    func storedTotalAmount(fromEnteredAmount enteredAmount: Double) -> Double {
        guard total >= 2, current >= 2 else { return enteredAmount }
        return enteredAmount * Double(total)
    }

    /// The per-month installment charge for a given `enteredAmount`.
    func monthlyAmount(fromEnteredAmount enteredAmount: Double) -> Double {
        guard total >= 2 else { return enteredAmount }
        return storedTotalAmount(fromEnteredAmount: enteredAmount) / Double(total)
    }

    /// Computes the initial `(date, amountText, monthsText)` values for `EditTransactionSheet`
    /// when the user clicks a row on the Dashboard.
    ///
    /// Why this exists: in the database, a mid-stream MSI (say `5/12` in November) has
    /// `storedPurchaseDate` back-dated 4 months earlier (July) and `storedTotalAmount`
    /// equal to the 12-month total. If the Edit sheet loaded `storedPurchaseDate` (July)
    /// and `"12"`, then typing `"5/12"` would subtract *another* 4 months from July
    /// and turn `5/12` into `9/12`!
    ///
    /// Instead, the Edit sheet anchors on `displayedRowDate` (the date in the period
    /// the user is looking at) and pre-fills `monthsText` with `"5/12"` (plus the
    /// monthly payment when `current >= 2`) so re-saving is idempotent.
    static func editFormSeed(
        storedTotalAmount: Double,
        totalInstallments: Int,
        storedPurchaseDate: Date,
        displayedRowDate: Date?,
        installmentLabel: String?
    ) -> (date: Date, amountText: String, monthsText: String) {
        let effectiveDate = displayedRowDate ?? storedPurchaseDate
        guard totalInstallments >= 2 else {
            return (effectiveDate, String(storedTotalAmount), "1")
        }

        if let label = installmentLabel {
            let parsed = parse(label)
            if parsed.current >= 2 {
                let monthly = storedTotalAmount / Double(parsed.total)
                return (effectiveDate, String(monthly), parsed.smartString)
            }
        }
        return (effectiveDate, String(storedTotalAmount), String(totalInstallments))
    }
}
