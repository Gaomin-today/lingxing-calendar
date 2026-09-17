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
    public static let solarTermSupportedYears = 2025...2027
    public static let solarTermCoverageNote = "节气日期已核对 2025–2027 年香港天文台年表；其他年份暂未收录。"
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

    /// Returns only the term's Beijing civil date, not its precise astronomical instant.
    /// `nil` means no term on this day, or an uncovered year; use hasSolarTermData to distinguish.
    public func solarTerm(on date: Date) -> String? {
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let dates = Self.solarTermDays[year] else { return nil }
        let firstIndex = (month - 1) * 2
        if dates[firstIndex] == day { return Self.solarTermNames[firstIndex] }
        if dates[firstIndex + 1] == day { return Self.solarTermNames[firstIndex + 1] }
        return nil
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
    private static let solarTermNames = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
        "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑",
        "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]
    // Two day-of-month values for each Gregorian month. Transcribed and checked against
    // HKO Gregorian–Lunar Calendar Conversion Tables, 2025/2026/2027 (see docs/calendar-sources.md).
    // No approximation or model-generated fallback is used outside this table.
    private static let solarTermDays: [Int: [Int]] = [
        2025: [5,20, 3,18, 5,20, 4,20, 5,21, 5,21, 7,22, 7,23, 7,23, 8,23, 7,22, 7,21],
        2026: [5,20, 4,18, 5,20, 5,20, 5,21, 5,21, 7,23, 7,23, 7,23, 8,23, 7,22, 7,22],
        2027: [5,20, 4,19, 6,21, 5,20, 6,21, 6,21, 7,23, 8,23, 8,23, 8,23, 7,22, 7,22]
    ]
}
