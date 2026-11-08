import Foundation

// Date math for drawing a month calendar grid (used by `DayGridPicker`).
// Kept here, free of any UI, so it can be unit-tested (see `DateCalendarGridTests`).
extension Date {
    /// The cells of a 7-column month grid for this date's month.
    ///
    /// Starts with `nil` placeholders for the blank cells before day 1, then one
    /// `Date` per day of the month, each at the start of that day (midnight).
    /// How many blanks there are depends on the calendar's `firstWeekday`: October
    /// 2026 starts on a Thursday, so a Sunday-first week has 4 blanks and a
    /// Monday-first week has 3.
    ///
    /// - Parameter calendar: injectable so tests can pin the time zone / first
    ///   weekday; the app just uses the default `.current` (the Mac's settings).
    /// - Returns: `[Date?]` — an array of *optional* dates, where `nil` means "empty cell".
    func monthGridDays(calendar: Calendar = .current) -> [Date?] {
        // `guard let ... else { return [] }` unwraps both optionals or bails out early.
        guard let month = calendar.dateInterval(of: .month, for: self),
              let dayCount = calendar.range(of: .day, in: .month, for: self)?.count
        else { return [] }

        let firstDay = month.start   // day 1 at midnight
        // `.weekday` is 1 = Sunday … 7 = Saturday, regardless of locale.
        let weekdayOfFirst = calendar.component(.weekday, from: firstDay)
        // How far day 1 sits from the start of the week. `+ 7` keeps it positive
        // before `% 7` (Swift's `%` can return negatives).
        let leadingBlanks = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        let blanks = [Date?](repeating: nil, count: leadingBlanks)
        // `map` turns each offset 0, 1, 2… into that day's date.
        let days: [Date?] = (0..<dayCount).map { offset in
            calendar.date(byAdding: .day, value: offset, to: firstDay)
        }
        return blanks + days
    }
}

extension Calendar {
    /// Two-letter weekday names ("Su", "Mo", …) for the grid's header row, rotated
    /// so they start on this calendar's `firstWeekday` — Sunday in some regions,
    /// Monday in others — matching the column order of `monthGridDays`.
    var orderedWeekdaySymbols: [String] {
        // `shortWeekdaySymbols` is always Sunday-first ("Sun", "Mon", …, in the
        // calendar's language); keep the first two letters of each.
        let symbols = shortWeekdaySymbols.map { String($0.prefix(2)) }
        let shift = Swift.min(Swift.max(firstWeekday - 1, 0), symbols.count - 1)
        // Move the first `shift` names to the end: e.g. Monday-first → Mo…Sa, Su.
        return Array(symbols[shift...] + symbols[..<shift])
    }
}

/// Quick relative-date jumps shown beneath `DayGridPicker` so the user can hop
/// straight to a common past anchor (yesterday, a week ago, or the start of last
/// month's statement) in one click.
///
/// - `CaseIterable`: provides `QuickDatePreset.allCases` so the UI can loop over
///   them without hardcoding each button.
/// - `Identifiable`: lets SwiftUI's `ForEach` distinguish each chip.
enum QuickDatePreset: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case lastWeek = "Last Week"
    case lastMonth = "Last Month"

    var id: String { rawValue }

    /// Computes the target date (at start-of-day) relative to `referenceDate`.
    ///
    /// - Parameters:
    ///   - referenceDate: "now" (injectable so tests can pass a fixed date).
    ///   - calendar: the calendar to do the date math in (defaults to `.current`).
    func resolve(from referenceDate: Date = Date(), calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: referenceDate)
        switch self {
        case .today:
            return startOfToday
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        case .lastWeek:
            return calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
        case .lastMonth:
            // Jump to the 1st of the previous month so the calendar opens at the
            // beginning of that statement period.
            let thisMonthStart = calendar.dateInterval(of: .month, for: startOfToday)?.start ?? startOfToday
            return calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? startOfToday
        }
    }
}
