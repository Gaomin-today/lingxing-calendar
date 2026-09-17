import Foundation

/// An explicit traditional rule input, never inferred from a name or profile.
public enum LuckGender: String, Codable, CaseIterable, Identifiable, Sendable {
    case male, female
    public var id: String { rawValue }
    public var label: String { self == .male ? "男" : "女" }
}

public enum LuckCycleDirection: String, Equatable, Sendable {
    case forward, backward
    public var label: String { self == .forward ? "顺排" : "逆排" }
}

public struct LuckStartOffset: Equatable, Sendable {
    public let years: Int
    public let months: Int
    public let days: Int
    public let hours: Int
    /// Difference between absolute clock minutes after second quantization.
    public let elapsedMinutes: Int
}

public struct LuckCycle: Identifiable, Equatable, Sendable {
    /// Starts at one. Time before the first handover has no fabricated 大运柱.
    public let index: Int
    public let pillar: Ganzhi
    public let start: Date
    /// Exclusive upper bound: the following cycle begins at this exact instant.
    public let end: Date
    public let nominalStartAge: Int
    public var id: Int { index }
    public func contains(_ instant: Date) -> Bool { start <= instant && instant < end }
}

public struct LuckFlowYear: Identifiable, Equatable, Sendable {
    /// Gregorian year in which the initial 立春 occurs in Beijing.
    public let year: Int
    public let pillar: Ganzhi
    public let start: Date
    public let end: Date
    public var id: Int { year }
    public func contains(_ instant: Date) -> Bool { start <= instant && instant < end }
}

public struct LuckFlowMonth: Identifiable, Equatable, Sendable {
    /// 寅月 is one; 丑月 is twelve. These are Jie months, not lunar months.
    public let index: Int
    public let pillar: Ganzhi
    public let start: Date
    public let end: Date
    public let startJieName: String
    public let endJieName: String
    public var label: String { "\(pillar.branch)月" }
    public var id: Int { index }
    public func contains(_ instant: Date) -> Bool { start <= instant && instant < end }
}

public struct LuckCycleChart: Equatable, Sendable {
    public let birthChart: FourPillarsChart
    public let gender: LuckGender
    public let direction: LuckCycleDirection
    public let startOffset: LuckStartOffset
    public let startAt: Date
    public let boundaryJie: SolarTermBoundary
    public let cycles: [LuckCycle]
    public var timeZoneIdentifier: String { birthChart.timeZoneIdentifier }
    public var birthInstant: Date { birthChart.instant }
    public var methodNote: String { LuckCycleEngine.methodNote }
    public func activeCycle(at instant: Date) -> LuckCycle? { cycles.first { $0.contains(instant) } }
}

public enum LuckCycleError: Error, Equatable, LocalizedError, Sendable {
    case birthTimeRequired
    case invalidCycleCount
    case invalidCalendarArithmetic
    case unsupportedFlowYear

    public var errorDescription: String? {
        switch self {
        case .birthTimeRequired: return "出生时间未知时，不能确定唯一的起运时刻与大运；请先补充时刻。"
        case .invalidCycleCount: return "本版支持生成 1 至 12 步大运。"
        case .invalidCalendarArithmetic: return "无法按所选时区计算交运日期。"
        case .unsupportedFlowYear: return "立春流年仅支持 1901–2099 年；超出部分暂不推算。"
        }
    }
}

public struct LuckCycleEngine: Sendable {
    public static let sourceTitle = "lunar-swift 1.1.8 · Yun sect 2 分钟换算"
    public static let sourceURL = FourPillarsEngine.algorithmSourceURL
    public static let methodNote = "阳年男、阴年女顺排，阴年男、阳年女逆排；年阴阳取立春年干。顺数至下一个节，逆数至上一个节。采用 sect 2 分钟法：3天折1年、360分钟折1月、12分钟折1日、1分钟折2小时。交节先按参考库四舍五入到整秒，再将两端舍秒取分钟后相减。交运按所选民用时区依次加年、月、日、小时；大运按真实交运瞬间连续划分十年，不在1月1日换运。未做真太阳时校正。"
    public static let boundaryNote = "交节时刻与出生记录的误差会放大到起运换算；分钟法所得交运时刻是传统规则的计算值，不是可观测的天文事件。"
    public static let flowMonthNote = "流月按十二节的精确交接时刻划分，立春起寅月，小寒起丑月；不是公历整月或农历月份。每段含开始时刻、不含结束时刻，交节瞬间归入新月。2099 流年的末段延续到 2100 立春，仅使用算法边界数据补齐。"
    private let fourPillars: FourPillarsEngine

    public init(fourPillars: FourPillarsEngine = FourPillarsEngine()) { self.fourPillars = fourPillars }

    public func calculate(for profile: BirthProfile, gender: LuckGender, cycleCount: Int = 10) throws -> LuckCycleChart {
        guard (1...12).contains(cycleCount) else { throw LuckCycleError.invalidCycleCount }
        guard let birth = try profile.resolvedBirthDate() else { throw LuckCycleError.birthTimeRequired }
        let zone = try profile.validatedTimeZone()
        let chart = try fourPillars.chart(at: birth, timeZone: zone, dayBoundary: profile.dayBoundary)
        let forward = chart.year.stemIndex.isMultiple(of: 2) == (gender == .male)
        let boundary = forward ? chart.nextJie : chart.previousJie
        let earlier = forward ? birth : boundary.date
        let later = forward ? boundary.date : birth
        // The reference library first rounds the astronomical JD to a Solar
        // second, then subtractMinute discards seconds. Reproduce both steps:
        // 59.8 seconds must carry to the next minute before this subtraction.
        // UTC minutes keep DST clock changes out of the astronomical interval.
        func referenceMinute(_ date: Date) -> Double { floor(floor(date.timeIntervalSince1970 + 0.5) / 60) }
        let minutes = max(0, Int(referenceMinute(later) - referenceMinute(earlier)))
        let offset = LuckStartOffset(years: minutes / 4320, months: minutes % 4320 / 360,
                                     days: minutes % 360 / 12, hours: minutes % 12 * 2, elapsedMinutes: minutes)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var start = birth
        for (component, value) in [(Calendar.Component.year, offset.years), (.month, offset.months),
                                   (.day, offset.days), (.hour, offset.hours)] {
            guard let next = calendar.date(byAdding: component, value: value, to: start) else {
                throw LuckCycleError.invalidCalendarArithmetic
            }
            start = next
        }
        var cycles: [LuckCycle] = []
        for index in 1...cycleCount {
            // Always anchor to the original handover; a leap-day clamp in one
            // decade must not shift every later decade away from February 29.
            guard let lower = calendar.date(byAdding: .year, value: (index - 1) * 10, to: start),
                  let upper = calendar.date(byAdding: .year, value: index * 10, to: start), lower < upper else {
                throw LuckCycleError.invalidCalendarArithmetic
            }
            cycles.append(LuckCycle(index: index, pillar: Ganzhi(index: chart.month.index + (forward ? index : -index)),
                                    start: lower, end: upper,
                                    nominalStartAge: calendar.component(.year, from: lower) - profile.birthYear + 1))
        }
        return LuckCycleChart(birthChart: chart, gender: gender, direction: forward ? .forward : .backward,
                              startOffset: offset, startAt: start, boundaryJie: boundary, cycles: cycles)
    }

    /// Full 立春-to-立春 intervals that intersect this cycle. A ten-year cycle
    /// usually touches eleven flow years because its handover is not at 立春.
    /// Unsupported years are omitted; a wholly unsupported cycle throws.
    public func flowYears(in cycle: LuckCycle) throws -> [LuckFlowYear] {
        var beijing = Calendar(identifier: .gregorian)
        beijing.timeZone = FourPillarsEngine.defaultTimeZone
        let first = max(1901, beijing.component(.year, from: cycle.start) - 1)
        let last = min(2099, beijing.component(.year, from: cycle.end))
        guard first <= last else { throw LuckCycleError.unsupportedFlowYear }
        let years = try (first...last).map { try flowYear($0) }
            .filter { $0.start < cycle.end && cycle.start < $0.end }
        guard !years.isEmpty else { throw LuckCycleError.unsupportedFlowYear }
        return years
    }

    public func flowYear(_ year: Int) throws -> LuckFlowYear {
        guard FourPillarsEngine.supportedYears.contains(year) else { throw LuckCycleError.unsupportedFlowYear }
        let start = try lichun(year)
        let end = try lichun(year + 1)
        return LuckFlowYear(year: year, pillar: Ganzhi(index: year - 4), start: start, end: end)
    }

    public func flowMonths(in flowYear: LuckFlowYear) throws -> [LuckFlowMonth] {
        guard FourPillarsEngine.supportedYears.contains(flowYear.year) else { throw LuckCycleError.unsupportedFlowYear }
        let boundaries = try (flowYear.year...flowYear.year + 1)
            .flatMap { try fourPillars.boundaryTerms(in: $0) }
            .filter { $0.isJie && flowYear.start <= $0.date && $0.date <= flowYear.end }
            .sorted { $0.date < $1.date }
        let expectedIndices = Array(stride(from: 2, through: 22, by: 2)) + [0, 2]
        guard boundaries.count == 13, boundaries.map(\.index) == expectedIndices,
              boundaries.first?.date == flowYear.start, boundaries.last?.date == flowYear.end else {
            throw FourPillarsError.incompleteSolarTerms
        }
        return try (0..<12).map { offset in
            let lower = boundaries[offset]
            let upper = boundaries[offset + 1]
            guard lower.date < upper.date else { throw FourPillarsError.incompleteSolarTerms }
            let stem = (flowYear.pillar.stemIndex % 5 * 2 + 2 + offset) % 10
            let branch = (2 + offset) % 12
            let pillar = Ganzhi(index: (0..<60).first { $0 % 10 == stem && $0 % 12 == branch }!)
            return LuckFlowMonth(index: offset + 1, pillar: pillar, start: lower.date, end: upper.date,
                                 startJieName: lower.name, endJieName: upper.name)
        }
    }

    private func lichun(_ year: Int) throws -> Date {
        // Keep an injected provider for the 2100 padding boundary as well.
        let terms = try fourPillars.boundaryTerms(in: year)
        guard let term = terms.first(where: { $0.index == 2 }) else { throw FourPillarsError.incompleteSolarTerms }
        return term.date
    }
}
