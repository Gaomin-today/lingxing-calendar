import Foundation
import LunarSwift

/// All calls that instantiate LunarSwift calendar objects share this lock because
/// upstream LunarYear has a mutable, process-wide single-year cache.
internal enum LunarRuntimeAccess {
    static let lock = NSRecursiveLock()

    static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

public struct AlmanacPosition: Identifiable, Equatable, Sendable {
    public let label: String
    public let raw: String
    public let direction: String
    public var id: String { label }
}

public struct AlmanacPalace: Identifiable, Equatable, Sendable {
    public let palace: String
    public let direction: String
    public let number: String
    public let element: String
    public let starName: String
    public var id: String { palace }
}

/// Traditional nine-star classification, not a measured probability or score.
public struct AlmanacNineStar: Equatable, Sendable {
    public let number: String
    public let color: String
    public let element: String
    public let name: String
    public let display: String
    public let palaces: [AlmanacPalace]
}

/// The two parts of 子时 are separate rows within one midnight-to-midnight date.
public struct AlmanacHour: Identifiable, Equatable, Sendable {
    public let id: Int
    public let label: String
    public let startMinute: Int
    /// Exclusive endpoint; 1440 means midnight of the next civil date.
    public let endMinute: Int
    public let ganZhi: String
    public let yi: [String]
    public let ji: [String]
    public let dutyGod: String
    public let dutyGodType: String
    public let luck: String
    public let clash: String
    public let sha: String
    public let positions: [AlmanacPosition]
    public let nineStar: AlmanacNineStar
    public var timeRange: String {
        String(format: "%02d:%02d–%02d:%02d", startMinute / 60, startMinute % 60, endMinute / 60, endMinute % 60)
    }
}

public struct AlmanacDay: Equatable, Sendable {
    public let date: Date
    public let dayGanZhi: String
    public let yi: [String]
    public let ji: [String]
    public let auspiciousGods: [String]
    public let inauspiciousGods: [String]
    public let dutyGod: String
    public let dutyGodType: String
    public let luck: String
    public let clash: String
    public let sha: String
    public let positions: [AlmanacPosition]
    public let pengZu: [String]
    public let mansion: String
    public let mansionLuck: String
    public let officer: String
    public let liuYao: String
    public let wuHou: String
    public let hou: String
    public let dayLu: String
    public let fetalPosition: String
    public let monthFetalPosition: String
    public let moonPhase: String
    public let yearNineStar: AlmanacNineStar
    public let monthNineStar: AlmanacNineStar
    public let dayNineStar: AlmanacNineStar
    public let hours: [AlmanacHour]
    public var sourceLabel: String { AlmanacEngine.sourceLabel }
    public var sourceURL: String { AlmanacEngine.sourceURL }
    public var boundaryNote: String { AlmanacEngine.boundaryNote }
}

public enum AlmanacError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedYear
    case invalidInstant

    public var errorDescription: String? {
        switch self {
        case .unsupportedYear: return "黄历当前支持 1901–2099 年。"
        case .invalidInstant: return "无法读取这个日期。"
        }
    }
}

/// Local deterministic traditional data. Nothing here calls an LLM or labels an
/// observance as a statutory holiday. It deliberately keeps the library's whole-
/// day almanac rules separate from the exact solar-term/natal-chart APIs.
public final class AlmanacEngine: @unchecked Sendable {
    public static let shared = AlmanacEngine()
    public static let sourceLabel = "lunar-swift 1.1.8 · 传统黄历规则"
    public static let sourceURL = "https://github.com/6tail/lunar-swift/tree/a7ec0e9b29f84a5d98b09b9ffd31145f17470d56"
    public static let boundaryNote = "按北京时间民用日期查询；日黄历零点换日。月建和年、月九星按库的固定 UTC+8 交节日期切换，历史夏令时期间可与日历当地钟表的节气日期不同。时辰采用晚子时 23:00 换日。宜忌与吉凶为该版本传统规则，流派可能不同，不代表结果预测。"
    public static let supportedYears = 1901...2099
    private let calendar = CalendarEngine().gregorian
    private let lock = NSLock()
    private var days: [Int: AlmanacDay] = [:]
    private var recency: [Int] = []
    private let capacity = 256

    public init() {}

    /// A shared bounded cache prevents each SwiftUI body read from recomputing
    /// thirteen hours and their star boards. Only immutable value records escape.
    public func day(on date: Date) throws -> AlmanacDay {
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw AlmanacError.invalidInstant }
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = p.year, Self.supportedYears.contains(year) else { throw AlmanacError.unsupportedYear }
        guard let month = p.month, let day = p.day else { throw AlmanacError.invalidInstant }
        let key = year * 10_000 + month * 100 + day
        lock.lock()
        defer { lock.unlock() }
        if let cached = days[key] {
            recency.removeAll { $0 == key }
            recency.append(key)
            return cached
        }
        let value = LunarRuntimeAccess.withLock {
            makeDay(year: year, month: month, day: day, date: calendar.startOfDay(for: date))
        }
        if recency.count >= capacity { days.removeValue(forKey: recency.removeFirst()) }
        days[key] = value
        recency.append(key)
        return value
    }

    /// Fields depend on the civil time slot, not on elapsed seconds since midnight
    /// (which can differ on a historical daylight-saving transition day).
    public func hour(at date: Date) throws -> AlmanacHour {
        let value = try day(on: date)
        let hour = calendar.component(.hour, from: date)
        return value.hours[hour == 0 ? 0 : (hour + 1) / 2]
    }

    private func makeDay(year: Int, month: Int, day: Int, date: Date) -> AlmanacDay {
        let lunar = Solar(year: year, month: month, day: day, hour: 12).lunar
        return AlmanacDay(
            date: date, dayGanZhi: lunar.dayInGanZhi,
            yi: lunar.getDayYi(sect: 1), ji: lunar.getDayJi(sect: 1),
            auspiciousGods: lunar.dayJiShen, inauspiciousGods: lunar.dayXiongSha,
            dutyGod: lunar.dayTianShen, dutyGodType: lunar.dayTianShenType, luck: lunar.dayTianShenLuck,
            clash: lunar.dayChongDesc, sha: lunar.daySha, positions: dayPositions(lunar),
            pengZu: [lunar.pengZuGan, lunar.pengZuZhi], mansion: lunar.xiu + lunar.zheng + lunar.animal,
            mansionLuck: lunar.xiuLuck, officer: lunar.zhiXing, liuYao: lunar.liuYao,
            wuHou: lunar.wuHou, hou: lunar.hou, dayLu: lunar.dayLu,
            fetalPosition: lunar.dayPositionTai, monthFetalPosition: lunar.monthPositionTai,
            moonPhase: lunar.yueXiang, yearNineStar: star(lunar.getYearNineStar(sect: 2)),
            monthNineStar: star(lunar.getMonthNineStar(sect: 2)), dayNineStar: star(lunar.dayNineStar),
            hours: lunar.times.enumerated().map { makeHour($0.element, index: $0.offset) }
        )
    }

    private func makeHour(_ time: LunarTime, index: Int) -> AlmanacHour {
        let start = index == 0 ? 0 : (index * 2 - 1) * 60
        let end = index == 12 ? 1440 : (index * 2 + 1) * 60
        let label = index == 0 ? "早子时" : index == 12 ? "晚子时" : time.zhi + "时"
        return AlmanacHour(
            id: index, label: label, startMinute: start, endMinute: end, ganZhi: time.ganZhi,
            yi: time.yi, ji: time.ji, dutyGod: time.tianShen, dutyGodType: time.tianShenType,
            luck: time.tianShenLuck, clash: time.chongDesc, sha: time.sha,
            positions: [
                .init(label: "喜神", raw: time.positionXi, direction: time.positionXiDesc),
                .init(label: "财神", raw: time.positionCai, direction: time.positionCaiDesc),
                .init(label: "福神", raw: time.getPositionFu(sect: 2), direction: time.getPositionFuDesc(sect: 2)),
                .init(label: "阳贵", raw: time.positionYangGui, direction: time.positionYangGuiDesc),
                .init(label: "阴贵", raw: time.positionYinGui, direction: time.positionYinGuiDesc)
            ],
            // LunarTime.nineStar in this release differs around the late-year
            // solstice. The main wannianli engine calls Lunar.timeNineStar.
            nineStar: star(time.lunar.timeNineStar)
        )
    }

    private func dayPositions(_ lunar: Lunar) -> [AlmanacPosition] {
        [
            .init(label: "喜神", raw: lunar.dayPositionXi, direction: lunar.dayPositionXiDesc),
            .init(label: "财神", raw: lunar.dayPositionCai, direction: lunar.dayPositionCaiDesc),
            .init(label: "福神", raw: lunar.getDayPositionFu(sect: 2), direction: lunar.getDayPositionFuDesc(sect: 2)),
            .init(label: "阳贵", raw: lunar.dayPositionYangGui, direction: lunar.dayPositionYangGuiDesc),
            .init(label: "阴贵", raw: lunar.dayPositionYinGui, direction: lunar.dayPositionYinGuiDesc)
        ]
    }

    private func star(_ value: NineStar) -> AlmanacNineStar {
        let path = [("中", "中宫"), ("乾", "西北"), ("兑", "正西"), ("艮", "东北"), ("离", "正南"),
                    ("坎", "正北"), ("坤", "西南"), ("震", "正东"), ("巽", "东南")]
        let board = path.enumerated().map { offset, palace in
            let item = NineStar(index: (value.index + offset) % 9)
            return AlmanacPalace(palace: palace.0, direction: palace.1, number: item.number,
                                 element: item.wuXing, starName: item.nameInXuanKong)
        }
        return AlmanacNineStar(number: value.number, color: value.color, element: value.wuXing,
                               name: value.nameInXuanKong, display: value.description, palaces: board)
    }
}
