import Foundation

/// A valid member of the sixty-pair cycle; index zero is 甲子.
public struct Ganzhi: Equatable, Hashable, Codable, Sendable {
    public let index: Int
    public var stemIndex: Int { index % 10 }
    public var branchIndex: Int { index % 12 }
    public var stem: String { Self.stems[stemIndex] }
    public var branch: String { Self.branches[branchIndex] }
    public var text: String { stem + branch }

    public init(index: Int) { self.index = (index % 60 + 60) % 60 }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let index = try container.decode(Int.self)
        guard (0..<60).contains(index) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ganzhi index must be 0...59")
        }
        self.index = index
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(index)
    }

    private static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
}

/// An absolute solar-longitude crossing. January 小寒 is index 0, followed
/// chronologically by the other 23 terms; only even indices change a month pillar.
public struct SolarTermBoundary: Identifiable, Equatable, Hashable, Sendable {
    public let index: Int
    public let date: Date
    public var name: String { Self.names[index] }
    public var isJie: Bool { index.isMultiple(of: 2) }
    public var id: String { "\(index)-\(date.timeIntervalSinceReferenceDate)" }

    public init(index: Int, date: Date) {
        self.index = (index % 24 + 24) % 24
        self.date = date
    }

    private static let names = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
        "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑",
        "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]
}

public struct FourPillarsChart: Equatable, Sendable {
    /// With unknown birth time, this is a representative instant for a candidate,
    /// not a claimed birth time. `natalCharts` never invents its hour pillar.
    public let instant: Date
    public let year: Ganzhi
    public let month: Ganzhi
    public let day: Ganzhi
    public let hour: Ganzhi?
    public let timeZoneIdentifier: String
    public let dayBoundary: BirthDayBoundary
    public let previousJie: SolarTermBoundary
    public let nextJie: SolarTermBoundary

    public init(
        instant: Date, year: Ganzhi, month: Ganzhi, day: Ganzhi, hour: Ganzhi?,
        timeZoneIdentifier: String, dayBoundary: BirthDayBoundary,
        previousJie: SolarTermBoundary, nextJie: SolarTermBoundary
    ) {
        self.instant = instant
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.timeZoneIdentifier = timeZoneIdentifier
        self.dayBoundary = dayBoundary
        self.previousJie = previousJie
        self.nextJie = nextJie
    }
}

public enum FourPillarsError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedYear
    case invalidInstant
    case solarTermDataUnavailable(Int)
    case incompleteSolarTerms

    public var errorDescription: String? {
        switch self {
        case .unsupportedYear: return "四柱计算仅支持 1901–2099 年。"
        case .invalidInstant: return "无法识别这个日期或时间。"
        case .solarTermDataUnavailable(let year): return "\(year) 年的交节时刻数据尚未就绪，暂不推算四柱。"
        case .incompleteSolarTerms: return "交节时刻数据不完整，暂不推算四柱。"
        }
    }
}

public struct FourPillarsEngine: Sendable {
    public static let supportedYears = 1901...2099
    public static let algorithmSource = "lunar-swift 1.1.8 · ShouXingUtil · MIT"
    public static let algorithmSourceURL = "https://github.com/6tail/lunar-swift/tree/a7ec0e9b29f84a5d98b09b9ffd31145f17470d56"
    public static let calculationNote = "年柱以立春、月柱以十二节的计算交界换柱；日时使用所选民用时区，不做真太阳时校正。交节时刻含 ΔT 模型估计，临近交界的出生记录需核对。"
    public static let lateZiNote = "零点换日只影响日柱；23:00 后的晚子时时干按次日日干起算，跨零点保持同一子时时柱，与 lunar-swift 口径一致。"
    /// Fixed modern Beijing offset; callers may supply an IANA zone to honour
    /// historical civil-time changes. Neither mode applies true solar time.
    public static let defaultTimeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    private let solarTermsProvider: @Sendable (Int) throws -> [SolarTermBoundary]

    public init() {
        self.solarTermsProvider = { try NativeSolarTermProvider.shared.terms(in: $0) }
    }

    /// Provider returns all solar terms for a Gregorian year, as absolute dates.
    /// Padding years 1900 and 2100 may be requested for edge-year boundaries.
    public init(solarTermsProvider: @escaping @Sendable (Int) throws -> [SolarTermBoundary]) {
        self.solarTermsProvider = solarTermsProvider
    }

    public func solarTerms(in year: Int) throws -> [SolarTermBoundary] {
        guard Self.supportedYears.contains(year) else { throw FourPillarsError.unsupportedYear }
        return try terms(in: year)
    }

    /// Internal consumers need the same provider's padding year to close the
    /// final supported flow-year interval at the following year's 立春.
    internal func boundaryTerms(in year: Int) throws -> [SolarTermBoundary] { try terms(in: year) }

    public func chart(
        at instant: Date, timeZone: TimeZone = Self.defaultTimeZone,
        dayBoundary: BirthDayBoundary = .midnight, includeHour: Bool = true
    ) throws -> FourPillarsChart {
        guard instant.timeIntervalSinceReferenceDate.isFinite else { throw FourPillarsError.invalidInstant }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let parts = local.dateComponents([.year, .month, .day, .hour], from: instant)
        guard let civilYear = parts.year, Self.supportedYears.contains(civilYear) else {
            throw FourPillarsError.unsupportedYear
        }
        let boundaries = try surroundingTerms(year: civilYear)
        let jie = boundaries.filter(\.isJie)
        guard let previous = jie.last(where: { $0.date <= instant }),
              let next = jie.first(where: { $0.date > instant }),
              let lichun = boundaries.last(where: { $0.index == 2 && $0.date <= instant }) else {
            throw FourPillarsError.incompleteSolarTerms
        }
        var beijing = Calendar(identifier: .gregorian)
        beijing.timeZone = Self.defaultTimeZone
        let pillarYear = beijing.component(.year, from: lichun.date)
        let yearPillar = Ganzhi(index: pillarYear - 4)
        let monthOffset = (previous.index / 2 + 11) % 12
        let monthStem = (yearPillar.stemIndex % 5 * 2 + 2 + monthOffset) % 10
        let monthBranch = (monthOffset + 2) % 12
        let monthPillar = Self.pair(stem: monthStem, branch: monthBranch)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let civilDay = utc.date(from: DateComponents(year: civilYear, month: parts.month, day: parts.day)),
              let anchor = utc.date(from: DateComponents(year: 2010, month: 3, day: 15)),
              let localHour = parts.hour else { throw FourPillarsError.invalidInstant }
        // HKO almanac's 2010-03-15 甲子 anchor; count civil days, not local elapsed hours.
        let dayIndex = Int((civilDay.timeIntervalSince(anchor) / 86400).rounded())
        let dayPillar = Ganzhi(index: dayIndex + (dayBoundary == .ziHour23 && localHour == 23 ? 1 : 0))
        // The 23:00–01:00 子 period is continuous. Under the midnight day-column
        // convention its late-子 hour stem still uses the following civil day's
        // stem, matching lunar-swift's sect=2 convention.
        let hourDay = Ganzhi(index: dayIndex + (localHour == 23 ? 1 : 0))
        let hourBranch = (localHour + 1) / 2 % 12
        let hourPillar = Self.pair(stem: (hourDay.stemIndex % 5 * 2 + hourBranch) % 10, branch: hourBranch)
        return FourPillarsChart(
            instant: instant, year: yearPillar, month: monthPillar, day: dayPillar,
            hour: includeHour ? hourPillar : nil, timeZoneIdentifier: timeZone.identifier,
            dayBoundary: dayBoundary, previousJie: previous, nextJie: next
        )
    }

    /// Unknown birth time means the whole real local day. Partition it at every
    /// relevant crossing, including an optional 23:00 day boundary, and return
    /// unique year/month/day combinations in chronological order. A candidate
    /// anchor is never presented as an inferred birth time or hour pillar.
    public func natalCharts(for profile: BirthProfile) throws -> [FourPillarsChart] {
        let zone = try profile.validatedTimeZone()
        if let instant = try profile.resolvedBirthDate() {
            return [try chart(at: instant, timeZone: zone, dayBoundary: profile.dayBoundary)]
        }
        let reference = try profile.referenceBirthDate()
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        guard let day = local.dateInterval(of: .day, for: reference), day.duration > 0 else {
            throw FourPillarsError.invalidInstant
        }
        var cuts = [day.start, day.end]
        cuts += try surroundingTerms(year: profile.birthYear)
            .filter { $0.isJie && $0.date > day.start && $0.date < day.end }.map(\.date)
        if profile.dayBoundary == .ziHour23 {
            cuts += localHourBoundaries(hour: 23, within: day, calendar: local)
            // A civil-clock jump may skip 23:00, yet jump from hour 22 to 23.
            // Partition at transitions as well rather than silently losing it.
            var cursor = day.start.addingTimeInterval(-1)
            for _ in 0..<16 {
                guard let transition = zone.nextDaylightSavingTimeTransition(after: cursor),
                      transition > cursor, transition < day.end else { break }
                if transition > day.start { cuts.append(transition) }
                cursor = transition.addingTimeInterval(1)
            }
        }
        cuts = Array(Set(cuts)).sorted()
        var seen = Set<[Int]>()
        var result: [FourPillarsChart] = []
        for (start, end) in zip(cuts, cuts.dropFirst()) where start < end {
            let sample = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            let candidate = try chart(at: sample, timeZone: zone, dayBoundary: profile.dayBoundary, includeHour: false)
            if seen.insert([candidate.year.index, candidate.month.index, candidate.day.index]).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    private func terms(in year: Int) throws -> [SolarTermBoundary] {
        let terms = try solarTermsProvider(year)
        guard !terms.isEmpty, terms.allSatisfy({ $0.date.timeIntervalSinceReferenceDate.isFinite }) else {
            throw FourPillarsError.incompleteSolarTerms
        }
        return terms.sorted { $0.date < $1.date }
    }

    private func surroundingTerms(year: Int) throws -> [SolarTermBoundary] {
        try (year - 1...year + 1).flatMap { try terms(in: $0) }.sorted { $0.date < $1.date }
    }

    private static func pair(stem: Int, branch: Int) -> Ganzhi {
        // Engine-generated stems and branches always have matching parity.
        Ganzhi(index: (0..<60).first { $0 % 10 == stem && $0 % 12 == branch }!)
    }

    private func localHourBoundaries(hour: Int, within interval: DateInterval, calendar: Calendar) -> [Date] {
        let parts = calendar.dateComponents([.year, .month, .day], from: interval.start)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let wallAsUTC = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: hour)) else { return [] }
        var offsets = Set<Int>()
        // Invert actual tzdb offsets, including both sides of a fold. This also
        // avoids Foundation's repeatedTimePolicy quirks for half-hour folds.
        for step in stride(from: -48, through: 48, by: 1) {
            offsets.insert(calendar.timeZone.secondsFromGMT(for: wallAsUTC.addingTimeInterval(Double(step) * 3600)))
        }
        return offsets.map { wallAsUTC.addingTimeInterval(-Double($0)) }.filter { candidate in
            guard candidate > interval.start, candidate < interval.end else { return false }
            let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: candidate)
            return actual.year == parts.year && actual.month == parts.month && actual.day == parts.day
                && actual.hour == hour && actual.minute == 0 && actual.second == 0
        }
    }
}
