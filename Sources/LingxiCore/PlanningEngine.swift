import Foundation

public struct TimeSlot: Identifiable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public var id: String { "\(start.timeIntervalSinceReferenceDate)-\(end.timeIntervalSinceReferenceDate)" }
    public var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

public struct TimelineSegment: Identifiable, Equatable, Sendable {
    public let occurrence: EventOccurrence
    public let dayMinutesStart: Double
    public let dayMinutesEnd: Double
    public let column: Int
    public let columnCount: Int
    public var id: String { occurrence.id }

    public init(occurrence: EventOccurrence, dayMinutesStart: Double, dayMinutesEnd: Double, column: Int, columnCount: Int) {
        self.occurrence = occurrence
        self.dayMinutesStart = dayMinutesStart
        self.dayMinutesEnd = dayMinutesEnd
        self.column = column
        self.columnCount = columnCount
    }
}

/// Pure planning calculations. All boundaries use the same China Standard Time
/// as the lunar calendar and local event scheduler.
public struct PlanningEngine: Sendable {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        result.firstWeekday = 2
        return result
    }

    public init() {}

    public func weekDays(containing date: Date) -> [Date] {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return [] }
        let day = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    /// Checks the candidate's concrete interval against existing occurrences.
    /// Repeating existing events are expanded within that interval. It does not
    /// attempt an unbounded prediction of every future instance of a new series.
    /// Adjacent intervals do not conflict; tasks never occupy calendar time.
    public func conflicts(for event: CalendarEvent, among events: [CalendarEvent]) -> [EventOccurrence] {
        guard !event.isTask, event.start < event.end else { return [] }
        return EventScheduler().occurrences(
            of: events.filter { !$0.isTask && $0.id != event.id },
            from: event.start,
            to: event.end
        ).filter { $0.start < $0.end && $0.start < event.end && $0.end > event.start }
    }

    /// Finds maximal free intervals, clipped to the requested working hours.
    /// All-day events occupy time; tasks and zero-duration items do not.
    public func freeSlots(
        on date: Date, events: [CalendarEvent], startHour: Int = 9,
        endHour: Int = 21, minimumMinutes: Int = 30
    ) -> [TimeSlot] {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              (0...23).contains(startHour), (1...24).contains(endHour),
              startHour < endHour, minimumMinutes > 0 else { return [] }
        let day = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .hour, value: startHour, to: day),
              let end = calendar.date(byAdding: .hour, value: endHour, to: day) else { return [] }
        let busy = EventScheduler().occurrences(
            of: events.filter { !$0.isTask }, from: start, to: end
        ).filter { $0.start < $0.end }
        var cursor = start
        var slots: [TimeSlot] = []
        func appendGap(until next: Date) {
            if next.timeIntervalSince(cursor) >= Double(minimumMinutes) * 60 {
                slots.append(TimeSlot(start: cursor, end: next))
            }
        }
        for occurrence in busy {
            let busyStart = max(start, occurrence.start)
            let busyEnd = min(end, occurrence.end)
            if busyStart > cursor { appendGap(until: busyStart) }
            cursor = max(cursor, busyEnd)
        }
        if cursor < end { appendGap(until: end) }
        return slots
    }

    /// Clips timed events to the selected day and assigns side-by-side columns.
    /// Every connected overlap group shares its maximum concurrent column count.
    public func timelineSegments(on date: Date, events: [CalendarEvent]) -> [TimelineSegment] {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return [] }
        let day = calendar.startOfDay(for: date)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        let occurrences = EventScheduler().occurrences(
            of: events.filter { !$0.isAllDay && !$0.isTask }, from: day, to: nextDay
        ).filter { $0.start < $0.end }

        struct Positioned {
            let occurrence: EventOccurrence
            let start: Date
            let end: Date
            let column: Int
        }
        var group: [Positioned] = []
        var columnEnds: [Date] = []
        var groupEnd = day
        var result: [TimelineSegment] = []
        func flushGroup() {
            for item in group {
                result.append(TimelineSegment(
                    occurrence: item.occurrence,
                    dayMinutesStart: item.start.timeIntervalSince(day) / 60,
                    dayMinutesEnd: item.end.timeIntervalSince(day) / 60,
                    column: item.column,
                    columnCount: columnEnds.count
                ))
            }
            group = []
            columnEnds = []
        }

        for occurrence in occurrences {
            let start = max(day, occurrence.start)
            let end = min(nextDay, occurrence.end)
            if !group.isEmpty, start >= groupEnd { flushGroup() }
            let column: Int
            if let reusable = columnEnds.firstIndex(where: { $0 <= start }) {
                column = reusable
                columnEnds[reusable] = end
            } else {
                column = columnEnds.count
                columnEnds.append(end)
            }
            group.append(Positioned(occurrence: occurrence, start: start, end: end, column: column))
            groupEnd = max(start, max(groupEnd, end))
        }
        flushGroup()
        return result
    }
}
