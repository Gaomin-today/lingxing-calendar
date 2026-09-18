import Foundation
import Testing
@testable import LingxiCore

struct CalendarNavigationTests {
    private let navigation = CalendarNavigation()
    private var calendar: Calendar { navigation.calendar }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func parsesStrictCivilAndRelativeDates() throws {
        #expect(try navigation.parseDate("2026-09-18") == date(2026, 9, 18))
        #expect(try navigation.parseDate("2026/9/18") == date(2026, 9, 18))
        #expect(try navigation.parseDate("2026年9月18日") == date(2026, 9, 18))
        let reference = date(2026, 9, 18)
        #expect(try navigation.parseDate("今天", relativeTo: reference) == reference)
        #expect(try navigation.parseDate("明天", relativeTo: reference) == date(2026, 9, 19))
        #expect(try navigation.parseDate("昨天", relativeTo: reference) == date(2026, 9, 17))
    }

    @Test func rejectsAmbiguousOrInvalidDates() {
        #expect(throws: CalendarNavigation.Error.invalidDate("2026.09.18")) { try navigation.parseDate("2026.09.18") }
        #expect(throws: CalendarNavigation.Error.invalidDate("2026-02-30")) { try navigation.parseDate("2026-02-30") }
        #expect(throws: CalendarNavigation.Error.unsupportedDate) { try navigation.parseDate("1900-12-31") }
    }

    @Test func shiftsMonthAndYearWithEndOfMonthClamping() throws {
        #expect(try navigation.shift(date(2026, 1, 31), by: 1, period: .month) == date(2026, 2, 28))
        #expect(try navigation.shift(date(2028, 2, 29), by: 1, period: .year) == date(2029, 2, 28))
        #expect(try navigation.shift(date(2026, 1, 1), by: -1, period: .day) == date(2025, 12, 31))
    }

    @Test func shiftsWeeksAcrossYearAndClipsSupportedBounds() throws {
        #expect(try navigation.shift(date(2026, 1, 1), by: -1, period: .week) == date(2025, 12, 25))
        #expect(try navigation.shift(date(1901, 1, 1), by: -1, period: .day) == date(1901, 1, 1))
        #expect(try navigation.shift(date(2099, 12, 31), by: 1, period: .day) == date(2099, 12, 31))
    }
}
