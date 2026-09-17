import Foundation

/// Calendar facts are computed locally, independently of chat or a language model.
public struct DayInfo: Equatable, Sendable {
    public let lunarMonth: String
    public let lunarDay: String
    public var lunarDate: String { lunarMonth + lunarDay }
    public let yearGanZhi: String
    public let dayGanZhi: String
    public let zodiac: String
    public let solarTerm: String?
    public let numericLunarMonth: Int
    public let numericLunarDay: Int
    public let isLeapMonth: Bool
}

public struct CalendarEngine: Sendable {
    /// The entire first release uses Beijing civil time, regardless of the Mac's time zone.
    public static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    public static let solarTermSupportedYears = 1901...2099
    public static let solarTermCoverageNote = "节气覆盖 1901–2099 年，采用本地太阳黄经算法；2025–2027 年的 72 个节气日期已核对香港天文台年表。时刻为算法计算值。"
    public let gregorian: Calendar
    private let chinese: Calendar

    public init() {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = Self.timeZone
        gregorian.locale = Locale(identifier: "zh_CN")
        gregorian.firstWeekday = 2
        self.gregorian = gregorian
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = Self.timeZone
        chinese.locale = Locale(identifier: "zh_CN")
        self.chinese = chinese
    }

    public func info(for date: Date) -> DayInfo {
        let lunar = chinese.dateComponents([.year, .month, .day, .isLeapMonth], from: date)
        let month = lunar.month ?? 1
        let day = lunar.day ?? 1
        // Foundation's Chinese year is the 1-based position in the sexagenary cycle.
        // It changes at Chinese New Year, not at Lichun.
        let yearIndex = Self.positiveModulo((lunar.year ?? 1) - 1, 60)
        let leap = lunar.isLeapMonth == true
        return DayInfo(
            lunarMonth: (leap ? "闰" : "") + Self.monthNames[month - 1],
            lunarDay: Self.dayNames[day - 1],
            yearGanZhi: Self.ganZhi(index: yearIndex),
            dayGanZhi: dayGanZhi(for: date),
            zodiac: Self.animals[yearIndex % 12],
            solarTerm: solarTerm(on: date),
            numericLunarMonth: month,
            numericLunarDay: day,
            isLeapMonth: leap
        )
    }

    /// Always six weeks, beginning on Monday at 00:00 Beijing time.
    public func monthDays(containing date: Date) -> [Date] {
        guard let first = gregorian.dateInterval(of: .month, for: date)?.start else { return [] }
        let offset = (gregorian.component(.weekday, from: first) + 5) % 7
        guard let gridStart = gregorian.date(byAdding: .day, value: -offset, to: first) else { return [] }
        return (0..<42).compactMap { gregorian.date(byAdding: .day, value: $0, to: gridStart) }
    }

    public func festivals(on date: Date) -> [Festival] {
        let lunar = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
        // The catalog follows ordinary-month observance. Regional leap-month variants
        // require their own explicit sources and are not silently inferred here.
        guard lunar.isLeapMonth != true else { return [] }
        return FestivalCatalog.all.filter {
            $0.lunarMonth == lunar.month && $0.lunarDay == lunar.day
        }
    }

    public func hasSolarTermData(for date: Date) -> Bool {
        Self.solarTermSupportedYears.contains(gregorian.component(.year, from: date))
    }

    /// Returns the term label for its whole Beijing civil date. A date label does
    /// not mean the astronomical boundary has already occurred at that instant.
    public func solarTerm(on date: Date) -> String? {
        guard hasSolarTermData(for: date) else { return nil }
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return SolarTermDayCache.shared.labels(in: year, calendar: gregorian)[month * 100 + day]
    }

    /// All 24 astronomical boundaries, chronologically ordered, in an explicitly
    /// supported Gregorian year. Shares the natal-chart engine's astronomy cache.
    public func solarTerms(in year: Int) throws -> [SolarTermBoundary] {
        guard Self.solarTermSupportedYears.contains(year) else { throw FourPillarsError.unsupportedYear }
        return try NativeSolarTermProvider.shared.terms(in: year)
    }

    /// `previous` includes an exact hit; `next` is strictly after the instant.
    /// `onDay` is independent of whether today's boundary has already occurred.
    public func solarTermContext(at date: Date) throws -> SolarTermContext {
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw FourPillarsError.invalidInstant }
        let year = gregorian.component(.year, from: date)
        guard Self.solarTermSupportedYears.contains(year) else { throw FourPillarsError.unsupportedYear }
        let terms = try ((year - 1)...(year + 1)).flatMap { try NativeSolarTermProvider.shared.terms(in: $0) }
        guard let previous = terms.last(where: { $0.date <= date }),
              let next = terms.first(where: { $0.date > date }) else { throw FourPillarsError.incompleteSolarTerms }
        return SolarTermContext(previous: previous, next: next,
                                onDay: terms.first(where: { gregorian.isDate($0.date, inSameDayAs: date) }))
    }

    /// Civil-day naming: midnight is the boundary. This is not a Bazi birth-chart calculation.
    public func dayGanZhi(for date: Date) -> String {
        // HKO Almanac March 2010 identifies 15 March (lunar 1/30) as 甲子.
        // Count calendar days instead of seconds so historical DST does not shift a date.
        let anchor = gregorian.date(from: DateComponents(year: 2010, month: 3, day: 15))!
        let elapsed = gregorian.dateComponents([.day], from: anchor, to: gregorian.startOfDay(for: date)).day ?? 0
        return Self.ganZhi(index: Self.positiveModulo(elapsed, 60))
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        (value % divisor + divisor) % divisor
    }

    private static func ganZhi(index: Int) -> String {
        stems[index % 10] + branches[index % 12]
    }

    private static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let animals = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
    private static let monthNames = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let dayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]
}

public struct SolarTermContext: Equatable, Sendable {
    public let previous: SolarTermBoundary
    public let next: SolarTermBoundary
    public let onDay: SolarTermBoundary?
}

/// Month grids read dozens of days per render. Store the small civil-date index
/// once per year rather than comparing all 24 absolute instants for every cell.
private final class SolarTermDayCache: @unchecked Sendable {
    static let shared = SolarTermDayCache()
    private let lock = NSLock()
    private var years: [Int: [Int: String]] = [:]

    func labels(in year: Int, calendar: Calendar) -> [Int: String] {
        lock.lock()
        defer { lock.unlock() }
        if let found = years[year] { return found }
        guard let terms = try? NativeSolarTermProvider.shared.terms(in: year) else { return [:] }
        var labels: [Int: String] = [:]
        for term in terms {
            let parts = calendar.dateComponents([.month, .day], from: term.date)
            if let month = parts.month, let day = parts.day { labels[month * 100 + day] = term.name }
        }
        years[year] = labels
        return labels
    }
}
