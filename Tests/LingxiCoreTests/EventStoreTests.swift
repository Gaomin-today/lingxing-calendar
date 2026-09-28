import Foundation
import Testing
@testable import LingxiCore

struct EventStoreTests {
    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string + "+08:00")!
    }

    @Test func testPersistenceRoundTripsAndMissingFileStartsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/events.json")
        let repository = EventRepository(fileURL: url)
        #expect(try repository.load() == [])
        let event = CalendarEvent(
            title: "面试", start: date("2026-09-18T15:00:00").addingTimeInterval(0.123456),
            notes: "提前准备", repeatRule: .weekly, reminderMinutes: 30, isTask: true
        )
        try repository.save([event])
        #expect(try EventRepository(fileURL: url).load() == [event])
        try repository.save([])
        #expect(try repository.load() == [])
    }

    @Test func testCorruptFileThrowsWithoutChangingIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("not a calendar".utf8)
        try original.write(to: url)
        #expect(throws: (any Error).self) { try EventRepository(fileURL: url).load() }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func testCorruptionAfterLoadCannotBeOverwrittenByStaleOrEmptySave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = EventRepository(fileURL: directory.appendingPathComponent("events.json"))
        let event = CalendarEvent(title: "合成测试日程", start: date("2026-09-18T15:00:00"))
        try repository.save([event])
        let previouslyLoaded = try repository.load()
        for corrupt in [Data("interrupted write".utf8), Data("[{\"title\":\"missing required fields\"}]".utf8)] {
            try corrupt.write(to: repository.fileURL)
            #expect(throws: (any Error).self) { try repository.save(previouslyLoaded) }
            #expect(throws: (any Error).self) { try repository.save([]) }
            #expect(try Data(contentsOf: repository.fileURL) == corrupt)
        }
    }

    @Test func testDailyRepeatCrossesMonthAndDoesNotPrecedeSeriesStart() {
        let event = CalendarEvent(title: "静心", start: date("2026-01-31T09:00:00"), repeatRule: .daily)
        let occurrences = EventScheduler().occurrences(
            of: [event], from: date("2026-01-01T00:00:00"), to: date("2026-02-03T00:00:00")
        )
        #expect(occurrences.map(\.start) == [
            date("2026-01-31T09:00:00"), date("2026-02-01T09:00:00"), date("2026-02-02T09:00:00")
        ])
        #expect(Set(occurrences.map(\.id)).count == 3)
    }

    @Test func testWeeklyRepeatJumpsAcrossMonthsAndYears() {
        let event = CalendarEvent(title: "周会", start: date("2025-12-29T15:00:00"), repeatRule: .weekly)
        let occurrences = EventScheduler().occurrences(
            of: [event], from: date("2026-02-01T00:00:00"), to: date("2026-02-10T00:00:00")
        )
        #expect(occurrences.map(\.start) == [date("2026-02-02T15:00:00"), date("2026-02-09T15:00:00")])
    }

    @Test func testOvernightOccurrenceAndHalfOpenBoundaries() {
        let overnight = CalendarEvent(
            title: "夜间出行", start: date("2026-09-17T23:00:00"), end: date("2026-09-18T02:00:00")
        )
        let endingAtBoundary = CalendarEvent(
            title: "昨天", start: date("2026-09-17T22:00:00"), end: date("2026-09-18T00:00:00")
        )
        let nextDay = CalendarEvent(title: "明天", start: date("2026-09-19T00:00:00"))
        let scheduler = EventScheduler()
        let start = date("2026-09-18T00:00:00")
        let end = date("2026-09-19T00:00:00")
        #expect(scheduler.occurrences(of: [overnight, endingAtBoundary, nextDay], from: start, to: end).map(\.event.id) == [overnight.id])
        #expect(scheduler.occurrences(of: [overnight], from: end, to: start).isEmpty)
        #expect(scheduler.occurrences(of: [overnight], from: start, to: start).isEmpty)
    }

    @Test func testRepeatingOvernightEventRetainsPreviousDayInstance() {
        let event = CalendarEvent(
            title: "夜班", start: date("2026-01-30T23:00:00"), end: date("2026-01-31T02:00:00"), repeatRule: .daily
        )
        let occurrences = EventScheduler().occurrences(
            of: [event], from: date("2026-02-01T00:00:00"), to: date("2026-02-02T00:00:00")
        )
        #expect(occurrences.map(\.start) == [date("2026-01-31T23:00:00"), date("2026-02-01T23:00:00")])
    }

    @Test func testCompletedTasksAreExcludedButCompletedNonTasksRemain() {
        let start = date("2026-09-18T09:00:00")
        let task = CalendarEvent(start: start, isCompleted: true, isTask: true)
        let event = CalendarEvent(start: start, isCompleted: true)
        #expect(EventScheduler().occurrences(
            of: [task, event], from: date("2026-09-18T00:00:00"), to: date("2026-09-19T00:00:00")
        ).map(\.event.id) == [event.id])
    }

    @Test func testUpcomingRemindersAreFutureOrderedAndLimited() {
        let now = date("2026-09-17T12:00:00")
        let later = CalendarEvent(title: "晚会", start: date("2026-09-18T18:00:00"), repeatRule: .daily)
        let earlier = CalendarEvent(title: "晨会", start: date("2026-09-18T09:00:00"), repeatRule: .daily)
        let past = CalendarEvent(title: "已过提醒", start: date("2026-09-17T12:10:00"), reminderMinutes: 15)
        let reminders = upcomingNotifications(events: [later, earlier, past], now: now, limit: 3)
        #expect(reminders.map(\.title) == ["晨会", "晚会", "晨会"])
        #expect(reminders.first?.fireDate == date("2026-09-18T08:45:00"))
        #expect(reminders.allSatisfy { $0.fireDate > now })
        #expect(upcomingNotifications(events: [earlier], now: now, limit: 0).isEmpty)
    }

    @Test func testReminderCanBeInsideHorizonWhenEventIsOutside() {
        let now = date("2026-09-17T12:00:00")
        let event = CalendarEvent(title: "提前准备", start: date("2026-10-18T09:00:00"), reminderMinutes: 2 * 24 * 60)
        let reminders = upcomingNotifications(events: [event], now: now)
        #expect(reminders.map(\.fireDate) == [date("2026-10-16T09:00:00")])
    }

    @Test func testReminderCountHasNativeNotificationSafeCap() {
        let now = date("2026-09-17T00:00:00")
        let events = (9...12).map { hour in
            CalendarEvent(title: "日常", start: date("2026-09-17T\(hour < 10 ? "0" : "")\(hour):00:00"), repeatRule: .daily)
        }
        let reminders = upcomingNotifications(events: events, now: now, limit: 100)
        #expect(reminders.count == 60)
        #expect(reminders.last?.eventStart == date("2026-10-01T12:00:00"))
    }

    @Test func testInstantTaskIsVisibleAtItsStartButNotAtNextRangeBoundary() {
        let start = date("2026-09-18T09:00:00")
        let task = CalendarEvent(title: "待办", start: start, end: start, isTask: true)
        let scheduler = EventScheduler()
        #expect(scheduler.occurrences(of: [task], from: start, to: date("2026-09-18T10:00:00")).count == 1)
        #expect(scheduler.occurrences(of: [task], from: date("2026-09-18T08:00:00"), to: start).isEmpty)
    }
}
