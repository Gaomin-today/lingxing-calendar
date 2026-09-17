import Foundation
import Testing
@testable import LingxiCore

struct NotificationPlanTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func snooze(_ event: CalendarEvent, at fireDate: Date, id: String = UUID().uuidString) throws -> DeferredReminder {
        DeferredReminder(id: id, eventID: event.id, eventVersion: try #require(NotificationPlan.eventVersion(event)),
                         eventStart: event.start, fireDate: fireDate)
    }

    @Test func validSnoozeSurvivesRefreshAndRepositoryReload() throws {
        let event = CalendarEvent(title: "会议", start: now.addingTimeInterval(3600))
        let reminder = try snooze(event, at: now.addingTimeInterval(600))
        let loaded = try JSONDecoder().decode(CalendarEvent.self, from: JSONEncoder().encode(event))
        let first = NotificationPlan(events: [event], snoozes: [reminder], now: now)
        let restarted = NotificationPlan(events: [loaded], snoozes: [reminder], now: now.addingTimeInterval(60))
        #expect(first.retainedSnoozes == [reminder])
        #expect(restarted.retainedSnoozes == [reminder])
        // A later refresh must not schedule the same occurrence twice.
        #expect(first.regularReminders.isEmpty)
        #expect(restarted.regularReminders.isEmpty)
    }

    @Test func deletingCompletingOrEditingAnItemInvalidatesItsSnooze() throws {
        let event = CalendarEvent(title: "准备面试", start: now.addingTimeInterval(3600), isTask: true)
        let reminder = try snooze(event, at: now.addingTimeInterval(600))
        #expect(NotificationPlan(events: [], snoozes: [reminder], now: now).retainedSnoozes.isEmpty)
        var complete = event; complete.isCompleted = true
        #expect(NotificationPlan(events: [complete], snoozes: [reminder], now: now).retainedSnoozes.isEmpty)
        var moved = event; moved.start = moved.start.addingTimeInterval(900); moved.end = moved.end.addingTimeInterval(900)
        #expect(NotificationPlan(events: [moved], snoozes: [reminder], now: now).retainedSnoozes.isEmpty)
        var renamed = event; renamed.title = "复盘面试"
        #expect(NotificationPlan(events: [renamed], snoozes: [reminder], now: now).retainedSnoozes.isEmpty)
        var disabled = event; disabled.reminderMinutes = nil
        #expect(NotificationPlan(events: [disabled], snoozes: [reminder], now: now).retainedSnoozes.isEmpty)
    }

    @Test func expiredAndDuplicateSnoozesAreRemoved() throws {
        let event = CalendarEvent(start: now.addingTimeInterval(3600))
        let future = try snooze(event, at: now.addingTimeInterval(600), id: "future")
        let expired = try snooze(event, at: now, id: "expired")
        let plan = NotificationPlan(events: [event], snoozes: [expired, future, future], now: now)
        #expect(plan.retainedSnoozes == [future])
    }

    @Test func localCalendarDoesNotDuplicateAppleOrUndatedTaskNotifications() {
        let start = now.addingTimeInterval(3600)
        let local = CalendarEvent(title: "本地日程", start: start)
        let appleEvent = CalendarEvent(start: start, externalKind: "appleCalendar")
        let appleTask = CalendarEvent(start: start, isTask: true, externalKind: "appleReminders")
        let undated = CalendarEvent(start: start, isTask: true, taskHasDueDate: false)
        let plan = NotificationPlan(events: [local, appleEvent, appleTask, undated], snoozes: [], now: now)
        #expect(plan.regularReminders.map(\.eventID) == [local.id])
    }

    @Test func regularRemindersLeaveRoomForUserSnoozesAndKeepEarliestDates() {
        let events = (1...80).map { index in
            CalendarEvent(title: "日程 \(index)", start: now.addingTimeInterval(Double(index) * 3600))
        }
        let plan = NotificationPlan(events: events.reversed(), snoozes: [], now: now)
        #expect(plan.regularReminders.count == 52)
        #expect(plan.regularReminders.map(\.eventID) == events.prefix(52).map(\.id))
    }

    @Test func snoozesAndTestDeliveryTakePriorityWithinSixtyRequestBudget() throws {
        let regular = (1...80).map { index in CalendarEvent(start: now.addingTimeInterval(Double(index) * 3600)) }
        let snoozed = (1...20).map { _ in CalendarEvent(start: now.addingTimeInterval(-3600)) }
        let deferred = try snoozed.enumerated().map { index, event in
            try snooze(event, at: now.addingTimeInterval(Double(index + 1) * 600))
        }
        let plan = NotificationPlan(events: regular + snoozed, snoozes: deferred.reversed(), reservedCount: 1, now: now)
        #expect(plan.retainedSnoozes == deferred)
        #expect(plan.regularReminders.count == 39)
        #expect(plan.regularReminders.count + plan.retainedSnoozes.count + 1 == 60)
        #expect(plan.regularReminders.map(\.eventID) == regular.prefix(39).map(\.id))
    }

    @Test func excessiveDeferredRequestsKeepSoonestWithinBudget() throws {
        let events = (1...80).map { _ in CalendarEvent(start: now.addingTimeInterval(-3600)) }
        let deferred = try events.enumerated().map { index, event in
            try snooze(event, at: now.addingTimeInterval(Double(index + 1) * 600))
        }
        let plan = NotificationPlan(events: events, snoozes: deferred.reversed(), reservedCount: 1, now: now)
        #expect(plan.retainedSnoozes == Array(deferred.prefix(59)))
        #expect(plan.regularReminders.isEmpty)
    }

    @Test func fingerprintRejectsUnencodableDates() {
        let event = CalendarEvent(start: Date(timeIntervalSince1970: .infinity))
        #expect(NotificationPlan.eventVersion(event) == nil)
        #expect(!NotificationPlan.canNotify(event))
    }
}
