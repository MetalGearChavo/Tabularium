import Foundation

// Helpers for displaying and bucketing `Date` values.
extension Date {
    /// e.g. "June 2026" — used in the dashboard's month navigator.
    var monthYearString: String {
        formatted(.dateTime.month(.wide).year())
    }

    /// e.g. "Jun 1" — short label used in each transaction row.
    var shortDateString: String {
        formatted(.dateTime.month(.abbreviated).day())
    }

    /// e.g. "Wed, Jun 3" — used as the collapsible day header in the list view.
    var dayHeaderString: String {
        formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// e.g. "Mon, Oct 12, 2026" — the selected date in the Add sheet's day stepper.
    var longDayString: String {
        formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    /// The first instant of this date's month (e.g. June 1 at 00:00).
    /// Used to filter transactions to "this month".
    var startOfMonth: Date {
        // `Calendar` knows about months/timezones. `dateInterval(of:.month)` gives
        // the range covering this month; `.start` is its beginning.
        // `?? self` is a fallback: if the calculation somehow returns nil, just use
        // the date unchanged instead of crashing.
        Calendar.current.dateInterval(of: .month, for: self)?.start ?? self
    }

    /// The first instant of the *next* month — i.e. one past the end of this month.
    /// Filtering with `date < endOfMonth` therefore includes the whole month.
    var endOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)?.end ?? self
    }

    /// e.g. "Jun 20, 2026" — full short date with year, for the billing-cycle label.
    var shortDateYearString: String {
        formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// The credit-card statement period (start ..< end) that contains this date,
    /// for a card whose statement opens on `closingDay`.
    ///
    /// The closing day is the FIRST day of the cycle, so the period runs from that
    /// day through the day before next month's closing day. The returned `end` is
    /// *exclusive* (the next cycle's start), so filtering with
    /// `date >= start && date < end` includes the whole period.
    ///
    /// Example: `closingDay` 21, any date in late May/early June → (May 21, Jun 21),
    /// i.e. May 21 through Jun 20 inclusive.
    func billingPeriod(closingDay: Int) -> (start: Date, end: Date) {
        let cal = Calendar.current

        // The cycle start for the month that `date` falls in. We clamp the day to the
        // month's length so a closingDay of 31 lands on the last day of a short month
        // (e.g. Feb) instead of overflowing into the next one.
        func cycleStart(inMonthOf date: Date) -> Date {
            let lastDay = cal.range(of: .day, in: .month, for: date)?.count ?? 28
            var comps = cal.dateComponents([.year, .month], from: date)
            comps.day = min(closingDay, lastDay)
            return cal.startOfDay(for: cal.date(from: comps) ?? date)
        }

        let today = cal.startOfDay(for: self)
        let startThisMonth = cycleStart(inMonthOf: self)

        // If we're on/after this month's closing day, the current cycle started this
        // month; otherwise it started last month.
        let start: Date
        if today >= startThisMonth {
            start = startThisMonth
        } else {
            let prevMonth = cal.date(byAdding: .month, value: -1, to: self) ?? self
            start = cycleStart(inMonthOf: prevMonth)
        }

        // The next cycle's start is the exclusive end of this one.
        let nextMonth = cal.date(byAdding: .month, value: 1, to: start) ?? start
        let end = cycleStart(inMonthOf: nextMonth)
        return (start, end)
    }
}
