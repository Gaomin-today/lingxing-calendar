import Foundation

public enum EventRepeat: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, daily, weekly

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "不重复"
        case .daily: return "每天"
        case .weekly: return "每周"
        }
    }
}

public struct CalendarEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var start: Date
    public var end: Date
    public var notes: String
    public var isAllDay: Bool
    public var repeatRule: EventRepeat
    public var reminderMinutes: Int?
    public var isCompleted: Bool
    public var isTask: Bool
    /// Optional fields preserve compatibility with calendars saved before Apple integration.
    public var externalID: String?
    public var externalCalendarID: String?
    public var externalCalendarTitle: String?
    public var externalKind: String?
    public var externalReadOnly: Bool?
    public var externalModifiedAt: Date?
    public var externalOccurrenceDate: Date?
    public var externalRecurring: Bool?
    public var externalReadOnlyReason: String?
    public var taskHasDueDate: Bool?
    public var taskDueHasTime: Bool?
    public var location: String?

    public var isExternal: Bool { externalKind != nil }
    /// Older local tasks had an implicit due date in `start`.
    public var hasDueDate: Bool { taskHasDueDate != false }
    public var sourceLabel: String {
        guard let externalKind else { return isTask ? "本地待办" : "本地日程" }
        let source = externalKind == "appleReminders" ? "Apple 提醒事项" : "Apple 日历"
        guard let title = externalCalendarTitle, !title.isEmpty else { return source }
        return "\(source) · \(title)"
    }

    public init(
        id: UUID = UUID(),
        title: String = "新日程",
        start: Date = Date(),
        end: Date? = nil,
        notes: String = "",
        isAllDay: Bool = false,
        repeatRule: EventRepeat = .none,
        reminderMinutes: Int? = 15,
        isCompleted: Bool = false,
        isTask: Bool = false,
        externalID: String? = nil,
        externalCalendarID: String? = nil,
        externalCalendarTitle: String? = nil,
        externalKind: String? = nil,
        externalReadOnly: Bool? = nil,
        externalModifiedAt: Date? = nil,
        externalOccurrenceDate: Date? = nil,
        externalRecurring: Bool? = nil,
        externalReadOnlyReason: String? = nil,
        taskHasDueDate: Bool? = nil,
        taskDueHasTime: Bool? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end ?? start.addingTimeInterval(60 * 60)
        self.notes = notes
        self.isAllDay = isAllDay
        self.repeatRule = repeatRule
        self.reminderMinutes = reminderMinutes
        self.isCompleted = isCompleted
        self.isTask = isTask
        self.externalID = externalID
        self.externalCalendarID = externalCalendarID
        self.externalCalendarTitle = externalCalendarTitle
        self.externalKind = externalKind
        self.externalReadOnly = externalReadOnly
        self.externalModifiedAt = externalModifiedAt
        self.externalOccurrenceDate = externalOccurrenceDate
        self.externalRecurring = externalRecurring
        self.externalReadOnlyReason = externalReadOnlyReason
        self.taskHasDueDate = taskHasDueDate
        self.taskDueHasTime = taskDueHasTime
        self.location = location
    }
}

public struct EventOccurrence: Identifiable, Equatable, Sendable {
    public let event: CalendarEvent
    public let start: Date
    public let end: Date

    public var id: String {
        "\(event.id.uuidString)-\(start.timeIntervalSinceReferenceDate)"
    }

    public init(event: CalendarEvent, start: Date, end: Date) {
        self.event = event
        self.start = start
        self.end = end
    }
}

/// Local persistence deliberately propagates decoding errors. A damaged file is
/// never replaced with an empty calendar as a side effect of loading it.
public struct EventRepository: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [CalendarEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([CalendarEvent].self, from: data)
    }

    public func save(_ events: [CalendarEvent]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Foundation's reference-date encoding round-trips the stored Date
        // exactly, including fractions of a second.
        let data = try encoder.encode(events)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    public static func defaultURL() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("LingxingCalendar", isDirectory: true)
            .appendingPathComponent("events.json", isDirectory: false)
    }
}

public struct ScheduledReminder: Identifiable, Equatable, Sendable {
    public let id: String
    public let eventID: UUID
    public let title: String
    public let fireDate: Date
    public let eventStart: Date

    public init(id: String, eventID: UUID, title: String, fireDate: Date, eventStart: Date) {
        self.id = id
        self.eventID = eventID
        self.title = title
        self.fireDate = fireDate
        self.eventStart = eventStart
    }
}

public struct EventScheduler: Sendable {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return result
    }

    public init() {}

    /// Occurrences overlapping [from, to), including ones that began on an
    /// earlier day. Completed tasks are omitted. Repeating tasks resume when
    /// marked incomplete. Calendar arithmetic preserves local wall-clock time.
    public func occurrences(of events: [CalendarEvent], from: Date, to: Date) -> [EventOccurrence] {
        guard from.timeIntervalSinceReferenceDate.isFinite,
              to.timeIntervalSinceReferenceDate.isFinite,
              from < to else { return [] }

        var result: [EventOccurrence] = []
        let cal = calendar
        for event in events {
            guard !(event.isTask && (event.isCompleted || !event.hasDueDate)),
                  event.start.timeIntervalSinceReferenceDate.isFinite,
                  event.end.timeIntervalSinceReferenceDate.isFinite,
                  event.end >= event.start,
                  event.start < to else { continue }

            func appendIfOverlapping(start: Date, end: Date) {
                let overlaps = start == end
                    ? start >= from && start < to
                    : start < to && end > from
                if overlaps {
                    result.append(EventOccurrence(event: event, start: start, end: end))
                }
            }

            guard event.repeatRule != .none else {
                appendIfOverlapping(start: event.start, end: event.end)
                continue
            }

            let intervalDays = event.repeatRule == .daily ? 1 : 7
            // Jump near the requested range, retaining enough earlier instances
            // to include events whose duration spans several days or weeks.
            let elapsedDays = cal.dateComponents(
                [.day], from: cal.startOfDay(for: event.start), to: cal.startOfDay(for: from)
            ).day ?? 0
            let durationDays = cal.dateComponents(
                [.day], from: cal.startOfDay(for: event.start), to: cal.startOfDay(for: event.end)
            ).day ?? 0
            let subtraction = elapsedDays.subtractingReportingOverflow(durationDays)
            var index = 0
            if !subtraction.overflow, subtraction.partialValue > intervalDays {
                index = subtraction.partialValue / intervalDays - 1
            }
            var previousStart: Date?

            while true {
                let offset = index.multipliedReportingOverflow(by: intervalDays)
                guard !offset.overflow,
                      let start = cal.date(byAdding: .day, value: offset.partialValue, to: event.start),
                      let end = cal.date(byAdding: .day, value: offset.partialValue, to: event.end),
                      start < to,
                      previousStart.map({ start > $0 }) ?? true else { break }

                appendIfOverlapping(start: start, end: end)
                previousStart = start
                let next = index.addingReportingOverflow(1)
                guard !next.overflow else { break }
                index = next.partialValue
            }
        }

        return result.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
    }

    /// Returns the earliest reminders strictly after `now`, and before the end
    /// of the following 30 calendar days. At most 60 are returned so the native
    /// notification center retains capacity for other app notifications.
    public func upcomingNotifications(
        events: [CalendarEvent], now: Date, limit: Int = 60
    ) -> [ScheduledReminder] {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              limit > 0,
              let horizon = calendar.date(byAdding: .day, value: 30, to: now) else { return [] }

        var reminders: [ScheduledReminder] = []
        for event in events {
            guard !event.isExternal,
                  !(event.isTask && !event.hasDueDate),
                  let minutes = event.reminderMinutes, minutes >= 0,
                  let rangeStart = calendar.date(byAdding: .minute, value: minutes, to: now),
                  let rangeEnd = calendar.date(byAdding: .minute, value: minutes, to: horizon),
                  rangeEnd > rangeStart else { continue }

            // Shift the query by this event's lead time. Thus a reminder inside
            // the horizon is included even if its event falls beyond 30 days.
            for occurrence in occurrences(of: [event], from: rangeStart, to: rangeEnd) {
                guard let fire = calendar.date(byAdding: .minute, value: -minutes, to: occurrence.start),
                      fire > now, fire < horizon else { continue }
                reminders.append(ScheduledReminder(
                    id: occurrence.id,
                    eventID: event.id,
                    title: event.title,
                    fireDate: fire,
                    eventStart: occurrence.start
                ))
            }
        }
        reminders.sort {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            return $0.id < $1.id
        }
        return Array(reminders.prefix(min(limit, 60)))
    }
}

public func upcomingNotifications(
    events: [CalendarEvent], now: Date, limit: Int = 60
) -> [ScheduledReminder] {
    EventScheduler().upcomingNotifications(events: events, now: now, limit: limit)
}
