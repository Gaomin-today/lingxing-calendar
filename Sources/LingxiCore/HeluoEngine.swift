import Foundation
import LunarSwift

/// Native port of the user-supplied bazi-pro Heluo rule algorithm. It intentionally
/// fixes the reference's Gregorian-year / Jie-month mismatch and fallback-to-last
/// behavior. See docs/heluo-v0.6.md for the exact policy and reference comparisons.
public struct HeluoEngine: Sendable {
    public static let sourceTitle = "bazi-pro 河洛理数算法 · 灵性日历原生移植 v1"
    public static let methodNote = "河洛卦是传统规则的辅助视角。先天卦由四柱配数与元堂确定，后天卦由元堂变爻及内外卦变换确定。年卦统一按立春年递进，月卦按十二节交接，日卦六日一卦、当地零点递爻；交节瞬间另起新月。"
    private let fourPillars: FourPillarsEngine
    public init(fourPillars: FourPillarsEngine = FourPillarsEngine()) { self.fourPillars = fourPillars }

    public func calculate(for profile: BirthProfile, at instant: Date) throws -> HeluoReport {
        guard instant.timeIntervalSinceReferenceDate.isFinite else { throw HeluoError.invalidInstant }
        guard let birth = try profile.resolvedBirthDate() else { throw HeluoError.birthTimeRequired }
        guard let gender = profile.luckGender else { throw HeluoError.genderRequired }
        let zone = try profile.validatedTimeZone()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let civilYear = calendar.component(.year, from: instant)
        guard BirthProfile.supportedYears.contains(civilYear) else { throw HeluoError.unsupportedDate }
        let natal = try fourPillars.chart(at: birth, timeZone: zone, dayBoundary: profile.dayBoundary)
        guard let hour = natal.hour else { throw HeluoError.birthTimeRequired }
        let birthFlowYear = try flowYear(at: birth, civilYear: profile.birthYear)
        let queryFlowYear = try flowYear(at: instant, civilYear: civilYear)
        let age = queryFlowYear - birthFlowYear + 1
        let values = [natal.year, natal.month, natal.day, hour]
        var oddTotal = 0, evenTotal = 0
        for value in values {
            let stem = Self.stemNumbers[value.stemIndex]
            if stem.isMultiple(of: 2) { evenTotal += stem } else { oddTotal += stem }
            let branch = Self.branchNumbers[value.branchIndex]
            oddTotal += branch.0; evenTotal += branch.1
        }
        let tian = Self.reduce(oddTotal, pivot: 25, exact: 5)
        let di = Self.reduce(evenTotal, pivot: 30, exact: 3)
        var upper = Self.trigram(number: tian, birthYear: profile.birthYear, male: gender == .male, yearYang: natal.year.stemIndex.isMultiple(of: 2))
        var lower = Self.trigram(number: di, birthYear: profile.birthYear, male: gender == .male, yearYang: natal.year.stemIndex.isMultiple(of: 2))
        if natal.year.stemIndex.isMultiple(of: 2) != (gender == .male) { swap(&upper, &lower) }
        let first = Self.hexagram(lines: lower + upper)
        let yuanTang = Self.yuanTang(lines: first.lines, hourBranch: hour.branchIndex)
        let changed = Self.toggle(first.lines, at: yuanTang)
        let lunarMonth = LunarRuntimeAccess.withLock {
            Solar.fromYmdHms(year: profile.birthYear, month: profile.birthMonth, day: profile.birthDay,
                            hour: profile.birthHour, minute: profile.birthMinute).lunar.month
        }
        let secondLines: [Bool]
        if [3, 29, 39].contains(first.number), [5, 6].contains(yuanTang) {
            let shouldSwap = (yuanTang == 5) == !abs(lunarMonth).isMultiple(of: 2)
            secondLines = shouldSwap ? Self.swapTrigrams(changed) : changed
        } else { secondLines = Self.swapTrigrams(changed) }
        let second = Self.hexagram(lines: secondLines)
        let firstSegments = Self.segments(phase: "先天", hexagram: first, position: yuanTang, birthYear: birthFlowYear, age: 1)
        let segments = firstSegments + Self.segments(phase: "后天", hexagram: second, position: yuanTang,
                                                     birthYear: birthFlowYear, age: firstSegments.last!.endAge + 1)
        let current = segments.first { $0.startAge <= age && age <= $0.endAge }
        var issue: String?
        if instant < birth { issue = "所选时刻早于出生时刻，仅展示先天卦与后天卦。" }
        else if current == nil { issue = "已超出本算法先后天各六爻的 \(segments.last!.endAge) 个立春岁序；年、月、日卦不向外推演。这是算法覆盖范围，不是寿命判断。" }
        var yearGua: HeluoPeriodHexagram?, monthGua: HeluoPeriodHexagram?, dayGua: HeluoPeriodHexagram?
        if issue == nil, let current {
            let yearMarked = Self.yearGua(segment: current, year: queryFlowYear)
            let boundaries = try monthBoundaries(flowYear: queryFlowYear)
            yearGua = HeluoPeriodHexagram(marked: yearMarked, start: boundaries[0].date, end: boundaries[12].date,
                                         periodLabel: "\(queryFlowYear) 立春年", flowYear: queryFlowYear,
                                         monthIndex: nil, dayIndex: nil, blockIndex: nil, triggerLinePosition: nil)
            guard let index = (0..<12).first(where: { boundaries[$0].date <= instant && instant < boundaries[$0 + 1].date }) else {
                throw HeluoError.missingBoundary
            }
            let monthMarked = Self.monthGua(year: yearMarked, index: index + 1)
            let monthStart = boundaries[index].date, monthEnd = boundaries[index + 1].date
            monthGua = HeluoPeriodHexagram(marked: monthMarked, start: monthStart, end: monthEnd,
                                          periodLabel: "\(Self.monthNames[index])节月 · \(boundaries[index].name)起", flowYear: queryFlowYear,
                                          monthIndex: index + 1, dayIndex: nil, blockIndex: nil, triggerLinePosition: nil)
            let dayStart = calendar.startOfDay(for: instant)
            let anchor = calendar.startOfDay(for: monthStart)
            guard let offset = calendar.dateComponents([.day], from: anchor, to: dayStart).day, offset >= 0,
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { throw HeluoError.missingBoundary }
            let trigger = Self.advance(monthMarked.linePosition, by: 1 + offset / 6)
            let dayHexagram = Self.hexagram(lines: Self.toggle(monthMarked.hexagram.lines, at: trigger))
            let parts = calendar.dateComponents([.year, .month, .day], from: instant)
            dayGua = HeluoPeriodHexagram(marked: Self.mark(dayHexagram, at: offset % 6 + 1),
                                        start: max(dayStart, monthStart), end: min(nextDay, monthEnd),
                                        periodLabel: String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!),
                                        flowYear: queryFlowYear, monthIndex: index + 1, dayIndex: offset,
                                        blockIndex: offset / 6 + 1, triggerLinePosition: trigger)
        }
        var notes = [Self.methodNote,
                     "岁序以出生所在立春年为 1，每过立春加 1；不是周岁或法定年龄。阳爻管 9 年，阴爻管 6 年，先后天各轮行六爻。",
                     "采用档案当地钟表时间与 \(profile.dayBoundary.label)排四柱，节气按绝对时刻；日卦始终按当地自然日。未做真太阳时校正。",
                     "沿用参考脚本三元寄宫分段：1924 年前上元，1924–1983 中元，1984 年起下元；未推定 2044 年后新一轮三元。",
                     "卦名与卦象为传统资料；下方主题、提问是本应用原创的自我探索提示，不是吉凶概率或事件预言。"]
        if zone.secondsFromGMT(for: birth) != 8 * 3600 {
            notes.append("参考脚本通常使用固定 UTC+08:00；本档案使用 \(zone.identifier)，含其历史夏令时。出生四柱可能因此不同。至尊卦阴阳月例外仍按所填民用出生日期对应的中国农历月判定。")
        }
        return HeluoReport(profileID: profile.id, instant: instant, timeZoneIdentifier: zone.identifier,
                           tianNumber: tian, diNumber: di, xianTian: Self.mark(first, at: yuanTang),
                           houTian: Self.mark(second, at: yuanTang), year: yearGua, month: monthGua, day: dayGua,
                           nominalAge: age, lifeSegments: segments, currentLifeSegment: issue == nil ? current : nil,
                           flowUnavailableReason: issue, methodNotes: notes)
    }

    private func flowYear(at instant: Date, civilYear: Int) throws -> Int {
        let starts = try (civilYear - 1...civilYear + 1).flatMap { try fourPillars.boundaryTerms(in: $0) }
            .filter { $0.index == 2 && $0.date <= instant }.sorted { $0.date < $1.date }
        guard let start = starts.last else { throw HeluoError.missingBoundary }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar.component(.year, from: start.date)
    }

    private func monthBoundaries(flowYear: Int) throws -> [SolarTermBoundary] {
        let terms = try (flowYear...flowYear + 1).flatMap { try fourPillars.boundaryTerms(in: $0) }
        let starts = terms.filter { $0.index == 2 }.sorted { $0.date < $1.date }
        guard starts.count == 2 else { throw HeluoError.missingBoundary }
        let result = terms.filter { $0.isJie && starts[0].date <= $0.date && $0.date <= starts[1].date }.sorted { $0.date < $1.date }
        guard result.count == 13 else { throw HeluoError.missingBoundary }
        return result
    }

    private static let stemNumbers = [6, 2, 8, 7, 1, 9, 3, 4, 6, 2]
    private static let branchNumbers = [(1,6),(5,10),(3,8),(3,8),(5,10),(7,2),(7,2),(5,10),(9,4),(9,4),(5,10),(1,6)]
    private static let trigramBits = ["坤": 0, "震": 1, "坎": 2, "兑": 3, "艮": 4, "离": 5, "巽": 6, "乾": 7]
    private static let monthNames = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static func reduce(_ total: Int, pivot: Int, exact: Int) -> Int {
        let reduced = (total - 1) % pivot + 1
        if reduced == pivot { return exact }
        if [10, 20, 30].contains(reduced) { return reduced / 10 }
        return reduced >= 10 ? reduced % 10 : reduced
    }
    private static func trigram(number: Int, birthYear: Int, male: Bool, yearYang: Bool) -> [Bool] {
        let name: String
        if number != 5 { name = [1:"坎",2:"坤",3:"震",4:"巽",6:"乾",7:"兑",8:"艮",9:"离"][number]! }
        else if birthYear < 1924 { name = male ? "艮" : "坤" }
        else if birthYear > 1983 { name = male ? "离" : "兑" }
        else { name = male == yearYang ? "艮" : "坤" }
        return bits(trigramBits[name]!, count: 3)
    }
    private static func yuanTang(lines: [Bool], hourBranch: Int) -> Int {
        let yang = hourBranch < 6
        let main = lines.indices.filter { lines[$0] == yang }.map { $0 + 1 }
        let other = lines.indices.filter { lines[$0] != yang }.map { $0 + 1 }
        let sequence: [Int]
        switch main.count {
        case 1, 2: sequence = main + main + other
        case 3: sequence = main + main
        case 4, 5: sequence = main + other
        default: sequence = Array(1...6)
        }
        return sequence[hourBranch % 6]
    }
    private static func segments(phase: String, hexagram: HeluoHexagram, position: Int, birthYear: Int, age: Int) -> [HeluoLifeSegment] {
        var nextAge = age
        return (0..<6).map { offset in
            let line = advance(position, by: offset)
            let duration = hexagram.lines[line - 1] ? 9 : 6
            let segment = HeluoLifeSegment(phase: phase, marked: mark(hexagram, at: line), startAge: nextAge,
                                          endAge: nextAge + duration - 1, startYear: birthYear + nextAge - 1,
                                          endYear: birthYear + nextAge + duration - 2, duration: duration)
            nextAge += duration
            return segment
        }
    }
    private static func yearGua(segment: HeluoLifeSegment, year: Int) -> HeluoMarkedHexagram {
        let position = segment.marked.linePosition
        let base = segment.marked.hexagram.lines
        let offset = year - segment.startYear
        var lines = base, line = position
        if base[position - 1] {
            if !(segment.startYear - 4).isMultiple(of: 2) { lines = toggle(lines, at: position) }
            if offset >= 1 { line = advance(position, by: 3); lines = toggle(lines, at: line) }
            if offset >= 2 { line = position; lines = toggle(lines, at: line) }
            if offset >= 3 { for step in 3...offset { line = advance(position, by: step - 2); lines = toggle(lines, at: line) } }
        } else {
            lines = toggle(lines, at: position)
            if offset >= 1 { for step in 1...offset { line = advance(position, by: step); lines = toggle(lines, at: line) } }
        }
        return mark(hexagram(lines: lines), at: line)
    }
    private static func monthGua(year: HeluoMarkedHexagram, index: Int) -> HeluoMarkedHexagram {
        var oddLines = year.hexagram.lines
        for pair in 0..<6 {
            let oddPosition = advance(year.linePosition, by: 1 + pair)
            oddLines = toggle(oddLines, at: oddPosition)
            if index == pair * 2 + 1 { return mark(hexagram(lines: oddLines), at: oddPosition) }
            if index == pair * 2 + 2 {
                let even = advance(oddPosition, by: 3)
                return mark(hexagram(lines: toggle(oddLines, at: even)), at: even)
            }
        }
        preconditionFailure("Month index must be in 1...12")
    }
    private static func advance(_ position: Int, by offset: Int) -> Int { (position - 1 + offset) % 6 + 1 }
    private static func toggle(_ lines: [Bool], at position: Int) -> [Bool] {
        var result = lines; result[position - 1].toggle(); return result
    }
    private static func swapTrigrams(_ lines: [Bool]) -> [Bool] { Array(lines[3...]) + Array(lines[..<3]) }
    private static func bits(_ value: Int, count: Int) -> [Bool] { (0..<count).map { value & (1 << $0) != 0 } }
    private static func mark(_ hexagram: HeluoHexagram, at position: Int) -> HeluoMarkedHexagram {
        let yinYang = hexagram.lines[position - 1] ? "九" : "六"
        let ordinal = ["初", "二", "三", "四", "五", "上"][position - 1]
        return HeluoMarkedHexagram(hexagram: hexagram, linePosition: position,
                                  lineLabel: [1, 6].contains(position) ? ordinal + yinYang : yinYang + ordinal)
    }
    internal static func hexagram(lines: [Bool]) -> HeluoHexagram {
        let value = lines.enumerated().reduce(0) { $0 | ($1.element ? 1 << $1.offset : 0) }
        let index = kingWenBits.firstIndex(of: value)!
        let upperValue = value >> 3, lowerValue = value & 7
        let upper = trigramBits.first { $0.value == upperValue }!.key
        let lower = trigramBits.first { $0.value == lowerValue }!.key
        let theme = themes[index]
        return HeluoHexagram(number: index + 1, name: names[index], upper: upper, lower: lower, lines: lines,
                             theme: theme, reflection: "把「\(theme)」当作一个观察角度：今天哪件事值得先做一个小而可验证的尝试？结合真实安排与反馈决定下一步。")
    }
    // Public-domain King Wen sequence. Binary encoding is lower trigram in bits 0...2.
    private static let kingWenBits = [63,0,17,34,23,58,2,16,55,59,7,56,61,47,4,8,25,38,3,48,41,37,32,1,57,39,33,30,18,45,28,14,60,15,40,5,53,43,20,10,35,49,31,62,24,6,26,22,29,46,9,36,52,11,13,44,54,27,50,19,51,12,21,42]
    private static let names = ["乾为天","坤为地","水雷屯","山水蒙","水天需","天水讼","地水师","水地比","风天小畜","天泽履","地天泰","天地否","天火同人","火天大有","地山谦","雷地豫","泽雷随","山风蛊","地泽临","风地观","火雷噬嗑","山火贲","山地剥","地雷复","天雷无妄","山天大畜","山雷颐","泽风大过","坎为水","离为火","泽山咸","雷风恒","天山遁","雷天大壮","火地晋","地火明夷","风火家人","火泽睽","水山蹇","雷水解","山泽损","风雷益","泽天夬","天风姤","泽地萃","地风升","泽水困","水风井","泽火革","火风鼎","震为雷","艮为山","风山渐","雷泽归妹","雷火丰","火山旅","巽为风","兑为泽","风水涣","水泽节","风泽中孚","雷山小过","水火既济","火水未济"]
    private static let themes = ["主动与持续","承载与协作","起步与积累","求教与学习","等待与准备","分歧与协商","组织与纪律","联结与互助","小步积累","分寸与边界","交流与通畅","停顿与调整","共同目标","资源与责任","谦逊与校准","准备与行动","顺势与选择","整理与修复","靠近与照顾","观察与复盘","厘清障碍","表达与内容","减负与保护","回归与重启","真实与踏实","积累与克制","滋养与节律","负荷与支撑","困难与练习","清晰与依托","感应与沟通","恒常与坚持","退让与空间","力量与分寸","进展与反馈","保护与蓄力","分工与关系","差异与理解","阻碍与求助","松动与缓解","取舍与专注","补益与合作","决断与说明","相遇与边界","汇聚与协调","渐进与成长","受限与韧性","共享与维护","变化与准备","更新与承载","变化与安定","停下来观察","循序与耐心","角色与节奏","充实与节制","适应与安顿","细致与沟通","交流与倾听","疏通与整合","节制与规则","信任与一致","谨慎与细节","完成与维护","未竟与接续"]
}
