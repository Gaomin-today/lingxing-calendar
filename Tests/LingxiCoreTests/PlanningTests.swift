import Foundation
import Testing
@testable import LingxiCore

struct PlanningTests {
    private let engine = PlanningEngine()

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "+08:00")!
    }

    private func event(_ title: String, _ start: String, _ end: String) -> CalendarEvent {
        CalendarEvent(title: title, start: date(start), end: date(end))
    }

    @Test func weekStartsOnMondayAcrossYearBoundary() {
        let days = engine.weekDays(containing: date("2027-01-03T23:59:59"))
        #expect(days.count == 7)
        #expect(days.first == date("2026-12-28T00:00:00"))
        #expect(days.last == date("2027-01-03T00:00:00"))
        #expect(engine.weekDays(containing: date("2026-12-28T10:00:00")) == days)
    }

    @Test func conflictExcludesSelfTasksAndAdjacentEventsButFindsRepeatAndOvernight() {
        let candidate = event("新安排", "2026-09-18T00:00:00", "2026-09-18T01:00:00")
        let adjacent = event("刚结束", "2026-09-17T23:00:00", "2026-09-18T00:00:00")
        let overnight = event("夜班", "2026-09-17T23:30:00", "2026-09-18T00:30:00")
        var recurring = event("每日回顾", "2026-09-01T00:45:00", "2026-09-01T01:15:00")
        recurring.repeatRule = .daily
        var task = event("待办", "2026-09-18T00:10:00", "2026-09-18T00:50:00")
        task.isTask = true
        let conflicts = engine.conflicts(for: candidate, among: [task, candidate, adjacent, recurring, overnight])
        #expect(conflicts.map(\.event.id) == [overnight.id, recurring.id])
        #expect(conflicts.last?.start == date("2026-09-18T00:45:00"))
        #expect(engine.conflicts(for: task, among: [candidate]).isEmpty)
    }

    @Test func allDayEventConflictsAndBlocksFreeTime() {
        var holiday = event("全天外出", "2026-09-18T00:00:00", "2026-09-19T00:00:00")
        holiday.isAllDay = true
        let candidate = event("会议", "2026-09-18T10:00:00", "2026-09-18T11:00:00")
        #expect(engine.conflicts(for: candidate, among: [holiday]).map(\.event.id) == [holiday.id])
        #expect(engine.freeSlots(on: candidate.start, events: [holiday]).isEmpty)
        #expect(engine.timelineSegments(on: candidate.start, events: [holiday]).isEmpty)
        #expect(engine.freeSlots(on: date("2026-09-19T12:00:00"), events: [holiday]).map(\.durationMinutes) == [720])
    }

    @Test func freeSlotsMergeNestedAndAdjacentBusyIntervalsAndClipToHours() {
        let day = date("2026-09-18T12:00:00")
        let early = event("早会", "2026-09-18T08:00:00", "2026-09-18T10:00:00")
        let main = event("工作", "2026-09-18T10:30:00", "2026-09-18T12:00:00")
        let nested = event("重叠", "2026-09-18T10:45:00", "2026-09-18T11:00:00")
        let adjacent = event("午餐", "2026-09-18T12:00:00", "2026-09-18T13:00:00")
        let late = event("晚会", "2026-09-18T20:45:00", "2026-09-18T22:00:00")
        var task = event("任务", "2026-09-18T13:00:00", "2026-09-18T20:45:00")
        task.isTask = true
        let slots = engine.freeSlots(on: day, events: [late, nested, task, main, adjacent, early])
        #expect(slots == [
            TimeSlot(start: date("2026-09-18T10:00:00"), end: date("2026-09-18T10:30:00")),
            TimeSlot(start: date("2026-09-18T13:00:00"), end: date("2026-09-18T20:45:00"))
        ])
        #expect(engine.freeSlots(on: day, events: [early, main], minimumMinutes: 31).first?.start == date("2026-09-18T12:00:00"))
    }

    @Test func freeSlotsRespectRepeatAndPreviousDayCarryover() {
        var overnight = event("夜班", "2026-09-01T23:00:00", "2026-09-02T10:00:00")
        overnight.repeatRule = .daily
        #expect(engine.freeSlots(on: date("2026-09-18T12:00:00"), events: [overnight]) == [
            TimeSlot(start: date("2026-09-18T10:00:00"), end: date("2026-09-18T21:00:00"))
        ])
        #expect(engine.freeSlots(on: date("2026-09-18T12:00:00"), events: [], startHour: 23, endHour: 24).map(\.durationMinutes) == [60])
        #expect(engine.freeSlots(on: date("2026-09-18T12:00:00"), events: [], startHour: 10, endHour: 9).isEmpty)
    }

    @Test func timelineUsesSharedColumnCountForOverlapChainAndReusesColumns() {
        let a = event("A", "2026-09-18T09:00:00", "2026-09-18T10:00:00")
        let b = event("B", "2026-09-18T09:30:00", "2026-09-18T11:00:00")
        let c = event("C", "2026-09-18T10:00:00", "2026-09-18T10:45:00")
        let d = event("D", "2026-09-18T10:15:00", "2026-09-18T10:30:00")
        let e = event("E", "2026-09-18T11:00:00", "2026-09-18T12:00:00")
        let segments = engine.timelineSegments(on: a.start, events: [e, d, b, c, a])
        #expect(segments.map(\.columnCount) == [3, 3, 3, 3, 1])
        #expect(segments.map(\.column) == [0, 1, 0, 2, 0])
        #expect(segments.map(\.dayMinutesStart) == [540, 570, 600, 615, 660])
        #expect(segments.map(\.dayMinutesEnd) == [600, 660, 645, 630, 720])
    }

    @Test func timelineClipsBothEndsAcrossMidnightAndKeepsOccurrenceIdentity() {
        let overnight = event("夜间", "2026-09-17T23:00:00", "2026-09-18T02:00:00")
        let late = event("出行", "2026-09-18T23:00:00", "2026-09-19T02:00:00")
        let segments = engine.timelineSegments(on: date("2026-09-18T12:00:00"), events: [overnight, late])
        #expect(segments.map(\.dayMinutesStart) == [0, 1380])
        #expect(segments.map(\.dayMinutesEnd) == [120, 1440])
        #expect(segments.first?.occurrence.start == overnight.start)
        #expect(segments.first?.id == EventOccurrence(event: overnight, start: overnight.start, end: overnight.end).id)
    }

    @Test func undatedTasksNeverGetCalendarOccurrencesOrNotifications() {
        let start = date("2026-09-18T09:00:00")
        let task = CalendarEvent(title: "以后再做", start: start, isTask: true, taskHasDueDate: false)
        let scheduler = EventScheduler()
        #expect(scheduler.occurrences(of: [task], from: date("2026-09-18T00:00:00"), to: date("2026-09-19T00:00:00")).isEmpty)
        #expect(scheduler.upcomingNotifications(events: [task], now: date("2026-09-17T12:00:00")).isEmpty)
    }

    @Test func externalEventsStayVisibleButAppleOwnsTheirNotifications() {
        let start = date("2026-09-18T09:00:00")
        let external = CalendarEvent(title: "工作会议", start: start, externalID: "identifier", externalCalendarTitle: "工作", externalKind: "appleCalendar")
        let task = CalendarEvent(title: "交材料", start: start, isTask: true, externalKind: "appleReminders")
        #expect(external.isExternal)
        #expect(external.sourceLabel == "Apple 日历 · 工作")
        #expect(task.sourceLabel == "Apple 提醒事项")
        #expect(EventScheduler().occurrences(of: [external, task], from: date("2026-09-18T00:00:00"), to: date("2026-09-19T00:00:00")).count == 2)
        #expect(upcomingNotifications(events: [external, task], now: date("2026-09-17T12:00:00")).isEmpty)
    }

    @Test func legacyJSONDecodesWithoutNewMetadataAndNewMetadataRoundTrips() throws {
        let legacyJSON = """
        [{"id":"4F225D1F-580A-4515-BB69-9A9475C8A1C3","title":"旧待办","start":811785600,"end":811789200,"notes":"","isAllDay":false,"repeatRule":"none","reminderMinutes":15,"isCompleted":false,"isTask":true}]
        """
        let legacy = try JSONDecoder().decode([CalendarEvent].self, from: Data(legacyJSON.utf8))
        #expect(legacy.count == 1)
        #expect(legacy[0].hasDueDate)
        #expect(!legacy[0].isExternal)
        #expect(legacy[0].taskDueHasTime == nil)
        #expect(legacy[0].sourceLabel == "本地待办")
        let enriched = CalendarEvent(
            title: "系统任务", start: date("2026-09-18T09:00:00"), isTask: true,
            externalID: "reminder", externalCalendarID: "list", externalCalendarTitle: "日常",
            externalKind: "appleReminders", externalReadOnly: false,
            externalModifiedAt: date("2026-09-17T12:00:00"), externalOccurrenceDate: date("2026-09-18T09:00:00"),
            externalRecurring: true, externalReadOnlyReason: "", taskHasDueDate: false, taskDueHasTime: false,
            location: "上海"
        )
        #expect(try JSONDecoder().decode(CalendarEvent.self, from: JSONEncoder().encode(enriched)) == enriched)
    }
}
