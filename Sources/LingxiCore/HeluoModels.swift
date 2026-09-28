import Foundation

/// A deterministic traditional-rule result, not a prediction of external events.
public struct HeluoHexagram: Codable, Equatable, Sendable, Identifiable {
    public let number: Int
    public let name: String
    public let upper: String
    public let lower: String
    /// Bottom to top: true is an unbroken yang line. UI draws this array reversed.
    public let lines: [Bool]
    public let theme: String
    /// Original reflection prompt, not an attributed translation of the Zhouyi.
    public let reflection: String
    public var id: Int { number }
}

public struct HeluoMarkedHexagram: Codable, Equatable, Sendable {
    public let hexagram: HeluoHexagram
    /// 1 = initial (bottom) line; 6 = upper line.
    public let linePosition: Int
    public let lineLabel: String
}

public struct HeluoPeriodHexagram: Codable, Equatable, Sendable {
    public let marked: HeluoMarkedHexagram
    public let start: Date
    /// Exclusive; the new period owns an exact solar-term crossing.
    public let end: Date
    public let periodLabel: String
    public let flowYear: Int
    public let monthIndex: Int?
    /// Zero-based civil-day offset from the start Jie's local date.
    public let dayIndex: Int?
    public let blockIndex: Int?
    public let triggerLinePosition: Int?
}

public struct HeluoLifeSegment: Codable, Equatable, Sendable, Identifiable {
    public let phase: String
    public let marked: HeluoMarkedHexagram
    public let startAge: Int
    public let endAge: Int
    /// These are Li-Chun year labels, not January 1 dates.
    public let startYear: Int
    public let endYear: Int
    public let duration: Int
    public var id: String { "\(phase)-\(startAge)" }
}

public struct HeluoReport: Codable, Equatable, Sendable {
    public let profileID: UUID
    public let instant: Date
    public let timeZoneIdentifier: String
    public let tianNumber: Int
    public let diNumber: Int
    public let xianTian: HeluoMarkedHexagram
    public let houTian: HeluoMarkedHexagram
    public let year: HeluoPeriodHexagram?
    public let month: HeluoPeriodHexagram?
    public let day: HeluoPeriodHexagram?
    /// Rule age counting the natal Li-Chun year as one; not civil/legal age.
    public let nominalAge: Int
    public let lifeSegments: [HeluoLifeSegment]
    public let currentLifeSegment: HeluoLifeSegment?
    public let flowUnavailableReason: String?
    public let methodNotes: [String]
}

public enum HeluoError: Error, Equatable, LocalizedError, Sendable {
    case birthTimeRequired
    case genderRequired
    case invalidInstant
    case unsupportedDate
    case missingBoundary
    public var errorDescription: String? {
        switch self {
        case .birthTimeRequired: return "河洛卦需要完整四柱与时支，请先补充出生时刻；不会用默认中午代替。"
        case .genderRequired: return "河洛卦上下卦与寄宫规则需要档案中明确填写的排盘性别。"
        case .invalidInstant: return "查询时刻无效。"
        case .unsupportedDate: return "河洛卦查询日期仅支持 1901–2099 年。"
        case .missingBoundary: return "缺少完整交节边界，暂不能计算此时段的河洛卦。"
        }
    }
}
