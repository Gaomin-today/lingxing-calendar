import Foundation

/// Explicit opt-in only. A missing value in a legacy birth profile means off.
public enum BirthdayTracking: String, Codable, CaseIterable, Identifiable, Sendable {
    case solar, lunar
    public var id: String { rawValue }
    public var label: String { self == .solar ? "公历生日" : "农历生日" }
    public var ruleNote: String {
        switch self {
        case .solar: return "按出生档案中填写的公历月日，每年在首页显示。2 月 29 日在非闰年按 2 月 28 日。"
        case .lunar: return "按出生公历日期换算农历月日；闰月出生优先过对应闰月，无该闰月则过同序普通月。三十遇小月按该月末日。"
        }
    }
}


public enum DateReminderError: Error, LocalizedError, Equatable, Sendable {
    case daysBeforeOutOfRange, hourOutOfRange, minuteOutOfRange
    public var errorDescription: String? {
        switch self {
        case .daysBeforeOutOfRange: return "提醒提前天数需为 0–365 天。"
        case .hourOutOfRange: return "提醒小时需为 0–23。"
        case .minuteOutOfRange: return "提醒分钟需为 0–59。"
        }
    }
}

/// A local homepage/system-reminder preference. It does not itself schedule a
/// UserNotification; MilestoneNotificationPlan turns it into a dated request.
public struct DateReminder: Codable, Equatable, Sendable {
    public var daysBefore: Int
    public var hour: Int
    public var minute: Int
    public init(daysBefore: Int = 0, hour: Int = 9, minute: Int = 0) {
        self.daysBefore = daysBefore; self.hour = hour; self.minute = minute
    }
    public func validate() throws {
        guard (0...365).contains(daysBefore) else { throw DateReminderError.daysBeforeOutOfRange }
        guard (0...23).contains(hour) else { throw DateReminderError.hourOutOfRange }
        guard (0...59).contains(minute) else { throw DateReminderError.minuteOutOfRange }
    }
    private enum CodingKeys: String, CodingKey { case daysBefore, hour, minute }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(daysBefore: try c.decodeIfPresent(Int.self, forKey: .daysBefore) ?? 0,
                  hour: try c.decodeIfPresent(Int.self, forKey: .hour) ?? 9,
                  minute: try c.decodeIfPresent(Int.self, forKey: .minute) ?? 0)
        try validate()
    }
}

public enum MilestoneKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case countdown, anniversary
    public var id: String { rawValue }
    public var label: String { self == .countdown ? "倒计时" : "纪念日" }
    public var symbol: String { self == .countdown ? "hourglass" : "heart.text.square" }
}

public enum MilestoneError: Error, LocalizedError, Equatable, Sendable {
    case invalidTitle, invalidNote, invalidDate, invalidTimestamp, duplicateIdentifiers, noNextOccurrence
    public var errorDescription: String? {
        switch self {
        case .invalidTitle: return "标题需为 1–80 个字。"
        case .invalidNote: return "备注最多 2000 个字。"
        case .invalidDate: return "日期需为 1901–2099 年内真实的公历日期，格式 YYYY-MM-DD。"
        case .invalidTimestamp: return "记录时间无效。"
        case .duplicateIdentifiers: return "倒计时文件含重复标识，已保留原文件。"
        case .noNextOccurrence: return "下一次日期已超过 2099 年，本版暂不外推。"
        }
    }
}

public struct Milestone: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: MilestoneKind
    /// Civil Gregorian date in the calendar's Beijing date convention.
    public var targetDate: String
    public var repeatsAnnually: Bool
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date
    /// nil is the legacy/default-off value.
    public var reminder: DateReminder?

    public init(id: UUID = UUID(), title: String, kind: MilestoneKind = .countdown,
                targetDate: String, repeatsAnnually: Bool = false, note: String = "",
                createdAt: Date = Date(), updatedAt: Date = Date(), reminder: DateReminder? = nil) {
        self.id = id; self.title = title; self.kind = kind; self.targetDate = targetDate
        self.repeatsAnnually = repeatsAnnually; self.note = note
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.reminder = reminder
    }

    public static func draft(kind: MilestoneKind = .countdown, on date: Date) throws -> Milestone {
        Milestone(title: "", kind: kind, targetDate: try MilestoneCivilDate(instant: date).text)
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80 else { throw MilestoneError.invalidTitle }
        guard note.count <= 2000 else { throw MilestoneError.invalidNote }
        _ = try MilestoneCivilDate(text: targetDate)
        guard createdAt.timeIntervalSinceReferenceDate.isFinite, updatedAt.timeIntervalSinceReferenceDate.isFinite else { throw MilestoneError.invalidTimestamp }
        try reminder?.validate()
    }
}

public struct MilestoneRepository: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> [Milestone] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let values = try JSONDecoder().decode([Milestone].self, from: Data(contentsOf: fileURL))
        try Self.validate(values)
        return values
    }
    public func save(_ values: [Milestone]) throws {
        try Self.validate(values)
        // Never replace unreadable existing data with an empty/new collection.
        if FileManager.default.fileExists(atPath: fileURL.path) { _ = try load() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(values)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
    public static func defaultURL() -> URL {
        EventRepository.defaultURL().deletingLastPathComponent().appendingPathComponent("milestones.json")
    }
    private static func validate(_ values: [Milestone]) throws {
        guard Set(values.map(\.id)).count == values.count else { throw MilestoneError.duplicateIdentifiers }
        for value in values { try value.validate() }
    }
}

/// Strict, timezone-independent civil components; ordinal arithmetic never divides
/// a DST-sensitive elapsed duration by 86400 seconds.
internal struct MilestoneCivilDate: Comparable {
    let year: Int
    let month: Int
    let day: Int
    var text: String { String(format: "%04d-%02d-%02d", year, month, day) }
    static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    static var displayCalendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = CalendarEngine.timeZone; return c }
    var ordinal: Date { Self.utc.date(from: DateComponents(year: year, month: month, day: day))! }
    var noon: Date { Self.displayCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))! }
    init(text: String) throws {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, text.count == 10, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { throw MilestoneError.invalidDate }
        try self.init(year: y, month: m, day: d)
    }
    init(year: Int, month: Int, day: Int) throws {
        guard BirthProfile.supportedYears.contains(year), (1...12).contains(month), (1...31).contains(day),
              let instant = Self.utc.date(from: DateComponents(year: year, month: month, day: day)) else { throw MilestoneError.invalidDate }
        let parts = Self.utc.dateComponents([.year, .month, .day], from: instant)
        guard parts.year == year, parts.month == month, parts.day == day else { throw MilestoneError.invalidDate }
        self.year = year; self.month = month; self.day = day
    }
    init(instant: Date) throws {
        guard instant.timeIntervalSinceReferenceDate.isFinite else { throw MilestoneError.invalidDate }
        let c = Self.displayCalendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = c.year, let month = c.month, let day = c.day else { throw MilestoneError.invalidDate }
        try self.init(year: year, month: month, day: day)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.ordinal < rhs.ordinal }
    func days(to other: Self) -> Int { Self.utc.dateComponents([.day], from: ordinal, to: other.ordinal).day! }
}
