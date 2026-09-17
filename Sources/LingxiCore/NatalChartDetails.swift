import Foundation
import LunarSwift

public struct NatalHiddenStem: Identifiable, Equatable, Sendable {
    public let stemIndex: Int
    public let stem: String
    public let element: String
    public let tenGod: String
    public var id: Int { stemIndex }
}

public struct NatalPillarDetail: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let pillar: Ganzhi
    public let stemElement: String
    public let branchElement: String
    public let tenGod: String
    public let hiddenStems: [NatalHiddenStem]
    public let naYin: String
    /// The day master's twelve-stage relation to this pillar's branch (星运).
    public let dayMasterStage: String
    /// The pillar's own stem against its own branch (自坐).
    public let selfStage: String
    public let xun: String
    public let xunKong: String
}

public struct NatalChartDetails: Equatable, Sendable {
    public let chart: FourPillarsChart
    public let pillars: [NatalPillarDetail]
    public var dayMaster: String { chart.day.stem }
    public var scopeNote: String { NatalChartDetailsEngine.scopeNote }
}

/// Rule tables enrich an already calculated chart. No local clock fields are
/// fed back into LunarSwift, preserving the caller's absolute Jie and day policy.
public struct NatalChartDetailsEngine: Sendable {
    public static let sourceTitle = "lunar-swift 1.1.8 · LunarUtil / EightChar · MIT"
    public static let sourceURL = FourPillarsEngine.algorithmSourceURL
    public static let scopeNote = "藏干、十神、纳音、十二长生与旬空按固定规则表核对。星运以日干对各支，自坐以本柱天干对本支；这些名称不单独构成旺衰、喜用或吉凶结论。未知时柱不补造。"

    public init() {}

    public func details(for chart: FourPillarsChart) -> NatalChartDetails {
        var pillars = [
            pillarDetails(chart.year, dayMaster: chart.day, id: "year", label: "年柱"),
            pillarDetails(chart.month, dayMaster: chart.day, id: "month", label: "月柱"),
            pillarDetails(chart.day, dayMaster: chart.day, id: "day", label: "日柱")
        ]
        if let hour = chart.hour {
            pillars.append(pillarDetails(hour, dayMaster: chart.day, id: "hour", label: "时柱"))
        }
        return NatalChartDetails(chart: chart, pillars: pillars)
    }

    public func pillarDetails(_ pillar: Ganzhi, dayMaster: Ganzhi, id: String, label: String) -> NatalPillarDetail {
        let hidden = Self.hiddenStems[pillar.branch]!.map { stem in
            let index = Self.stems.firstIndex(of: stem)!
            return NatalHiddenStem(stemIndex: index, stem: stem, element: Self.elements[index / 2],
                                   tenGod: Self.tenGod(dayMaster: dayMaster.stem, other: stem))
        }
        return NatalPillarDetail(
            id: id, label: label, pillar: pillar,
            stemElement: Self.elements[pillar.stemIndex / 2], branchElement: Self.branchElements[pillar.branchIndex],
            tenGod: id == "day" ? "日主" : Self.tenGod(dayMaster: dayMaster.stem, other: pillar.stem),
            hiddenStems: hidden, naYin: Self.naYin[pillar.text]!,
            dayMasterStage: Self.stage(stem: dayMaster.stemIndex, branch: pillar.branchIndex),
            selfStage: Self.stage(stem: pillar.stemIndex, branch: pillar.branchIndex),
            xun: Self.xun[pillar.index / 10], xunKong: Self.xunKong[pillar.index / 10]
        )
    }

    private static func tenGod(dayMaster: String, other: String) -> String {
        tenGods[dayMaster + other]!
    }

    private static func stage(stem: Int, branch: Int) -> String {
        let offset = stageOffsets[stems[stem]]! + (stem.isMultiple(of: 2) ? branch : -branch)
        return stages[(offset % 12 + 12) % 12]
    }

    // Immutable snapshots avoid letting callers' mutations of the upstream
    // Objective-C-compatible public static vars change an in-use rule table.
    private static let stems = BaziRelationshipEngine.stems
    private static let elements = ["木", "火", "土", "金", "水"]
    private static let branchElements = ["水", "土", "木", "木", "土", "火", "火", "土", "金", "金", "土", "水"]
    private static let hiddenStems = LunarUtil.ZHI_HIDE_GAN
    private static let naYin = LunarUtil.NAYIN
    private static let tenGods = LunarUtil.SHI_SHEN
    private static let xun = LunarUtil.XUN
    private static let xunKong = LunarUtil.XUN_KONG
    private static let stages = EightChar.CHANG_SHENG
    private static let stageOffsets = EightChar.CHANG_SHENG_OFFSET
}
