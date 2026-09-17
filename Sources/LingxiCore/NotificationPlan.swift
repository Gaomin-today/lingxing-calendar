import Foundation
import CryptoKit

/// A system-persisted snooze, represented without depending on UserNotifications.
public struct DeferredReminder: Equatable, Sendable {
    public let id: String
    public let eventID: UUID
    public let eventVersion: String
    public let eventStart: Date
    public let fireDate: Date

    public init(id: String, eventID: UUID, eventVersion: String, eventStart: Date, fireDate: Date) {
        self.id = id
        self.eventID = eventID
        self.eventVersion = eventVersion
        self.eventStart = eventStart
        self.fireDate = fireDate
    }
}

/// Keeps valid snoozes across calendar refreshes and application restarts.
/// Eight slots are left available for user-requested snoozes and test delivery.
public struct NotificationPlan: Sendable {
    public static let pendingLimit = 60
    public static let regularLimit = 52
    public let retainedSnoozes: [DeferredReminder]
    public let regularReminders: [ScheduledReminder]

    public init(events: [CalendarEvent], snoozes: [DeferredReminder], reservedCount: Int = 0, now: Date) {
        let available = max(0, Self.pendingLimit - max(0, reservedCount))
        let current = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
        let valid = snoozes.filter { snooze in
            guard snooze.fireDate.timeIntervalSinceReferenceDate.isFinite,
                  snooze.eventStart.timeIntervalSinceReferenceDate.isFinite,
                  snooze.fireDate > now,
                  let event = current[snooze.eventID] else { return false }
            return Self.canNotify(event) && Self.eventVersion(event) == snooze.eventVersion
        }.sorted {
            $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate
        }
        var seen: Set<String> = []
        let retained = Array(valid.filter { seen.insert($0.id).inserted }.prefix(available))
        retainedSnoozes = retained
        let budget = min(Self.regularLimit, max(0, available - retained.count))
        regularReminders = Array(EventScheduler().upcomingNotifications(
            events: events.filter(Self.canNotify), now: now, limit: Self.pendingLimit
        ).filter { reminder in
            !retained.contains { $0.eventID == reminder.eventID && $0.eventStart == reminder.eventStart }
        }.prefix(budget))
    }

    public static func canNotify(_ event: CalendarEvent) -> Bool {
        event.externalKind == nil && !(event.isTask && (event.isCompleted || !event.hasDueDate))
            && event.reminderMinutes.map { $0 >= 0 } == true
            && event.start.timeIntervalSinceReferenceDate.isFinite
            && event.end.timeIntervalSinceReferenceDate.isFinite && event.end >= event.start
    }

    /// A stable cross-launch version. A moved, edited or completed item must not
    /// receive actions from an older notification, even when its UUID is unchanged.
    public static func eventVersion(_ event: CalendarEvent) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(event) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
