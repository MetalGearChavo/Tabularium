import Foundation
import Testing
@testable import Tabularium

/// Specs for the month-grid date math behind `DayGridPicker` (see
/// `Date+CalendarGrid.swift`). Every test builds its own `Calendar` with a fixed
/// time zone, locale and first weekday, so results never depend on the Mac's
/// region settings.
struct DateCalendarGridTests {

    /// A Gregorian calendar pinned to UTC/en_US with the given first weekday
    /// (1 = Sunday, 2 = Monday).
    private func calendar(firstWeekday: Int) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US")
        cal.firstWeekday = firstWeekday
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - monthGridDays

    @Test func sundayStartPadsOctober2026WithFourBlanks() {
        // Oct 1, 2026 is a Thursday → Su Mo Tu We are blank.
        let cal = calendar(firstWeekday: 1)
        let cells = date(2026, 10, 12, in: cal).monthGridDays(calendar: cal)

        #expect(cells.prefix(4).allSatisfy { $0 == nil })
        #expect(cells[4] == date(2026, 10, 1, in: cal))
        #expect(cells.compactMap { $0 }.count == 31)
        #expect(cells.last == date(2026, 10, 31, in: cal))
    }

    @Test func mondayStartPadsOctober2026WithThreeBlanks() {
        let cal = calendar(firstWeekday: 2)
        let cells = date(2026, 10, 12, in: cal).monthGridDays(calendar: cal)

        #expect(cells.prefix(3).allSatisfy { $0 == nil })
        #expect(cells[3] == date(2026, 10, 1, in: cal))
    }

    @Test func leapFebruaryHas29Days() {
        let cal = calendar(firstWeekday: 1)
        let cells = date(2028, 2, 10, in: cal).monthGridDays(calendar: cal)

        #expect(cells.compactMap { $0 }.count == 29)
    }

    @Test func cellsAreStartOfDayRegardlessOfTheInputTime() {
        // Asking from mid-afternoon must give the same midnight-based cells.
        let cal = calendar(firstWeekday: 1)
        let fromAfternoon = date(2026, 10, 12, hour: 15, in: cal).monthGridDays(calendar: cal)
        let fromFirst = date(2026, 10, 1, in: cal).monthGridDays(calendar: cal)

        #expect(fromAfternoon == fromFirst)
    }

    // MARK: - orderedWeekdaySymbols

    @Test func weekdaySymbolsStartOnSunday() {
        #expect(calendar(firstWeekday: 1).orderedWeekdaySymbols == ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"])
    }

    @Test func weekdaySymbolsStartOnMonday() {
        #expect(calendar(firstWeekday: 2).orderedWeekdaySymbols == ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"])
    }

    // MARK: - QuickDatePreset

    @Test func quickDatePresetsResolveRelativeToTodayAtMidnight() {
        let cal = calendar(firstWeekday: 1)
        let todayAfternoon = date(2026, 11, 7, hour: 19, in: cal)

        #expect(QuickDatePreset.today.resolve(from: todayAfternoon, calendar: cal) == date(2026, 11, 7, in: cal))
        #expect(QuickDatePreset.yesterday.resolve(from: todayAfternoon, calendar: cal) == date(2026, 11, 6, in: cal))
        #expect(QuickDatePreset.lastWeek.resolve(from: todayAfternoon, calendar: cal) == date(2026, 10, 31, in: cal))
        // Last month jumps to the 1st of the previous month — ready to enter a past statement from day 1.
        #expect(QuickDatePreset.lastMonth.resolve(from: todayAfternoon, calendar: cal) == date(2026, 10, 1, in: cal))
    }

    @Test func lastMonthHandlesYearBoundary() {
        let cal = calendar(firstWeekday: 1)
        let janMid = date(2026, 1, 18, in: cal)

        #expect(QuickDatePreset.lastMonth.resolve(from: janMid, calendar: cal) == date(2025, 12, 1, in: cal))
    }
}
