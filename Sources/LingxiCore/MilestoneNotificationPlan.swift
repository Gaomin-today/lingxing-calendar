import Foundation

public enum MilestoneNotificationSource: String, Codable, Sendable { case milestone, birthday }

/// Stable identity/version for a configured reminder. Services should retain this
/// metadata on requests so stale notifications can be removed after edits even if
/// their target date has left the current planning window.
public struct MilestoneNotificationSourceSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let sourceKey: String
    public let sourceID: UUID
    public let source: MilestoneNotificationSource
    public let version: String
    public init(id: String, sourceKey: String, sourceID: UUID, source: MilestoneNotificationSource, version: String) {
        self.id = id; self.sourceKey = sourceKey; self.sourceID = sourceID; self.source = source; self.version = version
    }
}

public struct MilestoneScheduledReminder: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sourceKey: String
    public let sourceID: UUID
    public let source: MilestoneNotificationSource
    public let sourceVersion: String
    public let title: String
    public let body: String
    public let targetDate: String
    public let fireDate: Date
    public var sourceSnapshot: MilestoneNotificationSourceSnapshot {
        MilestoneNotificationSourceSnapshot(id: sourceKey, sourceKey: sourceKey, sourceID: sourceID, source: source, version: sourceVersion)
    }
}

public enum MilestoneNotificationPlanError: Error, LocalizedError, Equatable, Sendable {
    case invalidNow, invalidWindowDays, duplicateSourceIDs
    public var errorDescription: String? {
        switch self {
        case .invalidNow: return "通知计划的当前时刻无效。"
        case .invalidWindowDays: return "计划窗口需为 1–365 个自然日。"
        case .duplicateSourceIDs: return "出生档案或倒计时包含重复标识，未生成通知计划。"
        }
    }
}

public struct MilestoneNotificationPlan: Codable, Equatable, Sendable {
    public static let schemaVersion = "milestone-notifications-v1"
    public let generatedAt: Date
    public let windowStart: Date
    public let windowEnd: Date
    public let sources: [MilestoneNotificationSourceSnapshot]
    public let reminders: [MilestoneScheduledReminder]

    public init(milestones: [Milestone], profiles: [BirthProfile], now: Date, windowDays: Int = 30) throws {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw MilestoneNotificationPlanError.invalidNow }
        guard (1...365).contains(windowDays) else { throw MilestoneNotificationPlanError.invalidWindowDays }
        let ids = milestones.map(\.id) + profiles.map(\.id)
        guard Set(ids).count == ids.count else { throw MilestoneNotificationPlanError.duplicateSourceIDs }
        for item in milestones { try item.validate() }
        for profile in profiles { try profile.validate() }
        let calendar = MilestoneCivilDate.displayCalendar
        let localStart = calendar.startOfDay(for: now)
        guard let localEnd = calendar.date(byAdding: .day, value: windowDays, to: localStart) else { throw MilestoneNotificationPlanError.invalidWindowDays }
        generatedAt = now; windowStart = now; windowEnd = localEnd
        var sourceList: [MilestoneNotificationSourceSnapshot] = []
        var remindersList: [MilestoneScheduledReminder] = []
        let engine = MilestoneEngine()
        func appendReminders(source: MilestoneNotificationSourceSnapshot, title: String, reminder: DateReminder,
                             kind: MilestoneKind, repeats: Bool, nextTarget: (Date) -> String?) {
            var probe = localStart
            // A 365-day lead can cross two annual boundaries (especially for
            // lunar birthdays), so inspect a small bounded sequence of targets.
            for _ in 0..<4 {
                guard let target = nextTarget(probe) else { break }
                if let request = try? Self.makeReminder(source: source, title: title, reminder: reminder,
                                                        target: target, now: now, windowEnd: localEnd,
                                                        calendar: calendar, kind: kind) {
                    remindersList.append(request)
                }
                guard repeats,
                      let targetDate = try? engine.civilDate(target),
                      let nextProbe = calendar.date(byAdding: .day, value: 1, to: targetDate) else { break }
                probe = nextProbe
            }
        }
        for item in milestones {
            guard let reminder = item.reminder else { continue }
            let snapshot = try Self.snapshot(for: item); sourceList.append(snapshot)
            appendReminders(source: snapshot, title: item.title, reminder: reminder, kind: item.kind,
                            repeats: item.repeatsAnnually) { probe in
                try? engine.occurrence(for: item, on: probe).targetDate
            }
        }
        for profile in profiles {
            guard profile.birthdayTracking != nil, let reminder = profile.birthdayReminder else { continue }
            guard let snapshot = try Self.snapshot(for: profile) else { continue }
            sourceList.append(snapshot)
            appendReminders(source: snapshot, title: "\(profile.name)的生日", reminder: reminder, kind: .anniversary,
                            repeats: true) { probe in
                try? engine.birthday(for: profile, on: probe)?.targetDate
            }
        }
        sources = sourceList.sorted { $0.sourceKey < $1.sourceKey }
        reminders = remindersList.sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
    }

    public static func snapshot(for milestone: Milestone) throws -> MilestoneNotificationSourceSnapshot {
        try milestone.validate()
        return snapshot(key: "milestone:\(milestone.id.uuidString)", id: milestone.id, source: .milestone, version: try AutomationSnapshot.revision(milestone))
    }
    public static func snapshot(for profile: BirthProfile) throws -> MilestoneNotificationSourceSnapshot? {
        try profile.validate()
        guard profile.birthdayTracking != nil, profile.birthdayReminder != nil else { return nil }
        return snapshot(key: "birthday:\(profile.id.uuidString)", id: profile.id, source: .birthday, version: try AutomationSnapshot.revision(profile))
    }
    private static func snapshot(key: String, id: UUID, source: MilestoneNotificationSource, version: String) -> MilestoneNotificationSourceSnapshot {
        MilestoneNotificationSourceSnapshot(id: key, sourceKey: key, sourceID: id, source: source, version: version)
    }

    /// Validates metadata without requiring the source to still be within the
    /// 30-day planning window. Service can use this on a delivered request.
    public static func isValid(_ reminder: MilestoneScheduledReminder, milestones: [Milestone], profiles: [BirthProfile]) -> Bool {
        guard let current: MilestoneNotificationSourceSnapshot = {
            switch reminder.source {
            case .milestone: guard let item = milestones.first(where: { $0.id == reminder.sourceID }) else { return nil }; return try? snapshot(for: item)
            case .birthday: guard let profile = profiles.first(where: { $0.id == reminder.sourceID }) else { return nil }; return try? snapshot(for: profile)
            }
        }(), current.sourceKey == reminder.sourceKey, current.version == reminder.sourceVersion else { return false }
        return reminder.id.hasPrefix(reminder.sourceKey + "|") && reminder.fireDate.timeIntervalSinceReferenceDate.isFinite
    }

    private static func fireDate(target: String, reminder: DateReminder, calendar: Calendar) throws -> Date {
        let targetDate = try MilestoneCivilDate(text: target)
        guard let reminderDay = calendar.date(byAdding: .day, value: -reminder.daysBefore, to: targetDate.noon) else { throw MilestoneError.noNextOccurrence }
        let parts = calendar.dateComponents([.year, .month, .day], from: reminderDay)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: reminder.hour, minute: reminder.minute)) else { throw MilestoneError.noNextOccurrence }
        return date
    }

    private static func makeReminder(source: MilestoneNotificationSourceSnapshot, title: String, reminder: DateReminder,
                                     target: String, now: Date, windowEnd: Date, calendar: Calendar, kind: MilestoneKind) throws -> MilestoneScheduledReminder? {
        try reminder.validate(); let targetDate = try MilestoneCivilDate(text: target)
        let fireDate = try Self.fireDate(target: targetDate.text, reminder: reminder, calendar: calendar)
        guard fireDate >= now, fireDate < windowEnd else { return nil }
        let id = "\(source.sourceKey)|\(targetDate.text)|\(String(format: "%02d:%02d", reminder.hour, reminder.minute))"
        let dayWord = reminder.daysBefore == 0 ? "今天" : "提前 \(reminder.daysBefore) 天"
        let body = "「\(title)」\(dayWord)到达（\(targetDate.text)）。"
        _ = kind
        return MilestoneScheduledReminder(id: id, sourceKey: source.sourceKey, sourceID: source.sourceID, source: source.source,
            sourceVersion: source.version, title: title, body: body, targetDate: targetDate.text, fireDate: fireDate)
    }
}
