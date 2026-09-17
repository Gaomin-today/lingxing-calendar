import Foundation

public enum BirthDayBoundary: String, Codable, CaseIterable, Identifiable, Sendable {
    case midnight
    case ziHour23

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .midnight: return "零点换日"
        case .ziHour23: return "子初（23:00）换日"
        }
    }
}

public enum BirthProfileError: Error, LocalizedError, Equatable, Sendable {
    case yearOutOfRange
    case invalidDate
    case invalidTime
    case invalidTimeZone
    case nonexistentLocalTime
    case nonexistentLocalDate
    case duplicateIdentifiers

    public var errorDescription: String? {
        switch self {
        case .yearOutOfRange: return "出生年份仅支持 1901–2099 年。"
        case .invalidDate: return "请填写真实的公历日期，例如 2 月不能有 30 日。"
        case .invalidTime: return "出生小时需为 0–23，分钟需为 0–59。"
        case .invalidTimeZone: return "请选择有效的 IANA 时区，例如 Asia/Shanghai；不接受模糊缩写或直接填写 UTC 偏移。"
        case .nonexistentLocalTime: return "这个当地时刻因夏令时或时区调整而不存在，请核对出生记录和时区。"
        case .nonexistentLocalDate: return "这个当地日期因时区调整而被跳过，请核对出生记录和时区。"
        case .duplicateIdentifiers: return "出生档案包含重复标识，已保留原文件，请先修复档案数据。"
        }
    }
}

/// Civil birth information, stored separately from calendars and AI settings.
/// Birthplace is a note only: it never supplies an inferred time zone, longitude
/// correction, or true solar time. The boundary policy affects later chart
/// calculation, never the resolution of the recorded birth instant itself.
public struct BirthProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var birthYear: Int
    public var birthMonth: Int
    public var birthDay: Int
    public var birthHour: Int
    public var birthMinute: Int
    public var birthTimeKnown: Bool
    public var timeZoneIdentifier: String
    public var birthplace: String
    public var dayBoundary: BirthDayBoundary
    /// Optional so existing local archives remain readable without migration.
    public var luckGender: LuckGender?
    public var strengthAssumption: BaziStrengthAssumption?

    public static let supportedYears = 1901...2099
    public static let repeatedTimePolicyDescription = "当地时钟回拨造成重复时刻时，采用该时刻第一次出现所对应的时间；请核对出生记录。"

    public init(
        id: UUID = UUID(), name: String = "", birthYear: Int = 1990,
        birthMonth: Int = 1, birthDay: Int = 1, birthHour: Int = 12,
        birthMinute: Int = 0, birthTimeKnown: Bool = false,
        timeZoneIdentifier: String = "Asia/Shanghai", birthplace: String = "",
        dayBoundary: BirthDayBoundary = .midnight,
        luckGender: LuckGender? = nil, strengthAssumption: BaziStrengthAssumption? = nil
    ) {
        self.id = id
        self.name = name
        self.birthYear = birthYear
        self.birthMonth = birthMonth
        self.birthDay = birthDay
        self.birthHour = birthHour
        self.birthMinute = birthMinute
        self.birthTimeKnown = birthTimeKnown
        self.timeZoneIdentifier = timeZoneIdentifier
        self.birthplace = birthplace
        self.dayBoundary = dayBoundary
        self.luckGender = luckGender
        self.strengthAssumption = strengthAssumption
    }

    public func validate() throws { _ = try resolution() }

    /// An unknown clock time never becomes a claimed birth instant. Civil date
    /// and zone validation still runs, including wholly skipped local dates.
    public func resolvedBirthDate() throws -> Date? {
        let result = try resolution()
        return birthTimeKnown ? result.date : nil
    }

    /// For date-based candidates only. With unknown time this uses local noon;
    /// on a rare noon clock gap it uses the corresponding next valid local time.
    /// Engines must still treat that entire birth day as uncertain: this anchor
    /// must not settle a solar-term boundary, day-boundary variant, or hour pillar.
    public func referenceBirthDate() throws -> Date { try resolution().date }

    public func isBirthTimeAmbiguous() throws -> Bool {
        let result = try resolution()
        return birthTimeKnown && result.isAmbiguous
    }

    public func validatedTimeZone() throws -> TimeZone {
        // Foundation also accepts ad-hoc strings such as GMT+0800. Require a
        // tzdb area/link identifier (or the standard UTC/GMT names) instead.
        // knownTimeZoneIdentifiers omits valid links such as US/Eastern and
        // Etc/UTC, so supported slash-form links are accepted as well.
        let isAreaOrLink = timeZoneIdentifier.range(
            of: #"^(?:[A-Za-z0-9_+\-]+/)+[A-Za-z0-9_+\-]+$"#,
            options: .regularExpression
        ) != nil
        guard timeZoneIdentifier == "UTC" || timeZoneIdentifier == "GMT"
                || Self.knownTimeZoneIdentifiers.contains(timeZoneIdentifier) || isAreaOrLink,
              let zone = TimeZone(identifier: timeZoneIdentifier) else {
            throw BirthProfileError.invalidTimeZone
        }
        return zone
    }

    private static let knownTimeZoneIdentifiers = Set(TimeZone.knownTimeZoneIdentifiers)

    private struct Resolution {
        let date: Date
        let isAmbiguous: Bool
    }

    private func resolution() throws -> Resolution {
        guard Self.supportedYears.contains(birthYear) else { throw BirthProfileError.yearOutOfRange }
        guard (1...12).contains(birthMonth), (1...31).contains(birthDay) else { throw BirthProfileError.invalidDate }
        if birthTimeKnown, !(0...23).contains(birthHour) || !(0...59).contains(birthMinute) {
            throw BirthProfileError.invalidTime
        }
        let hour = birthTimeKnown ? birthHour : 12
        let minute = birthTimeKnown ? birthMinute : 0
        let components = DateComponents(
            year: birthYear, month: birthMonth, day: birthDay,
            hour: hour, minute: minute, second: 0
        )
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let civilAsUTC = utc.date(from: components),
              matches(civilAsUTC, in: utc, hour: hour, minute: minute) else {
            throw BirthProfileError.invalidDate
        }
        let zone = try validatedTimeZone()
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone

        // Resolve wall time by inverting actual tzdb offsets. In particular,
        // Foundation's nextDate(... repeatedTimePolicy: .last) can miss the
        // second occurrence of a half-hour fold (Australia/Lord_Howe).
        // Offsets are in seconds, preserving historical non-minute offsets.
        var offsets = Set<Int>()
        for step in stride(from: -48, through: 48, by: 3) {
            offsets.insert(zone.secondsFromGMT(for: civilAsUTC.addingTimeInterval(Double(step) * 3600)))
        }
        var cursor = civilAsUTC.addingTimeInterval(-48 * 3600)
        let upper = civilAsUTC.addingTimeInterval(48 * 3600)
        for _ in 0..<16 {
            guard let transition = zone.nextDaylightSavingTimeTransition(after: cursor),
                  transition > cursor, transition < upper else { break }
            offsets.insert(zone.secondsFromGMT(for: transition.addingTimeInterval(-1)))
            offsets.insert(zone.secondsFromGMT(for: transition.addingTimeInterval(1)))
            cursor = transition.addingTimeInterval(1)
        }
        let candidates = offsets.map { civilAsUTC.addingTimeInterval(-Double($0)) }
            .filter { matches($0, in: local, hour: hour, minute: minute) }
            .sorted()
        if let first = candidates.first {
            return Resolution(date: first, isAmbiguous: candidates.count > 1)
        }
        guard !birthTimeKnown else { throw BirthProfileError.nonexistentLocalTime }
        // Noon is only an anchor for an unknown time, so a noon DST gap does
        // not invalidate an otherwise real birthday. A skipped entire civil
        // date (for example Pacific/Apia 2011-12-30) is still rejected.
        guard let normalizedNoon = local.date(from: components),
              matchesCivilDate(normalizedNoon, in: local) else {
            throw BirthProfileError.nonexistentLocalDate
        }
        return Resolution(date: normalizedNoon, isAmbiguous: false)
    }

    private func matchesCivilDate(_ date: Date, in calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return parts.year == birthYear && parts.month == birthMonth && parts.day == birthDay
    }

    private func matches(_ date: Date, in calendar: Calendar, hour: Int, minute: Int) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return parts.year == birthYear && parts.month == birthMonth && parts.day == birthDay
            && parts.hour == hour && parts.minute == minute && parts.second == 0
    }
}

/// A malformed existing file is never replaced by an empty collection, even
/// when a caller mistakenly invokes save after a failed load. Recovery requires
/// an explicit repair or relocation of that file, outside this repository.
public struct BirthProfileRepository: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> [BirthProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let profiles = try JSONDecoder().decode([BirthProfile].self, from: Data(contentsOf: fileURL))
        try Self.validate(profiles)
        return profiles
    }

    public func save(_ profiles: [BirthProfile]) throws {
        try Self.validate(profiles)
        if FileManager.default.fileExists(atPath: fileURL.path) { _ = try load() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profiles)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func defaultURL() -> URL {
        EventRepository.defaultURL().deletingLastPathComponent().appendingPathComponent("profiles.json", isDirectory: false)
    }

    private static func validate(_ profiles: [BirthProfile]) throws {
        guard Set(profiles.map(\.id)).count == profiles.count else { throw BirthProfileError.duplicateIdentifiers }
        for profile in profiles { try profile.validate() }
    }
}
