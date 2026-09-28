import Foundation

/// An evidence direction within a traditional interpretive rule, not a probability.
public enum StrengthEvidenceDirection: String, Codable, Equatable, Sendable {
    case strong, weak, mixed, neutral
}

public struct StrengthAssessmentEvidence: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let category: String
    public let title: String
    public let observations: [String]
    public let ruleNote: String
    public let direction: StrengthEvidenceDirection
}

/// All decision inputs are deterministic natal facts. Manual premises and Agent
/// interpretations remain separate layers; they never alter this report.
public struct StrengthAssessmentReport: Codable, Equatable, Sendable {
    public let ruleVersion: String
    public let ruleName: String
    public let decisionID: String
    public let assessment: BaziStrengthAssumption
    public let label: String
    public let summary: String
    public let dayMaster: String
    public let candidateCount: Int
    public let evidence: [StrengthAssessmentEvidence]
    public let counterEvidence: [String]
    public let uncertainties: [String]
    public let scopeNote: String
    public let limitations: [String]
    public let sourceTitle: String
    public let sourceURL: String
}

/// Conservative, versioned ordinary 扶抑 screening. This is a published product
/// convention, not a claim that traditional schools share one numeric algorithm.
/// There is deliberately no summed element score, confidence percentage, or 用神.
public struct StrengthAssessmentEngine: Sendable {
    public static let ruleVersion = "ordinary-fuyi-v1.0"
    public static let ruleName = "普通扶抑 · 本地初判 v1"
    public static let scopeNote = "旺衰是传统命理中的结构描述，不代表体能、心理能力或人生好坏。本结果按公开的普通扶抑简化规则给出初步倾向，不是科学测量，不独立确定格局、喜用神或吉凶。"
    public static let limitations = [
        "月令按节气月的通行藏干本气观察，未按交节天数细分人元司令；辰戌丑未杂气月暂不定强弱。",
        "同五行藏干记作根气线索；本气与其他藏干分开记录，不把藏干条数折算成力量分。",
        "未建立完整的寒暖燥湿、格局、合化、刑害破和制化模型；涉及明显结构争议时保留未定。",
        "只分析出生原局；大运、流年与当日干支不会反向改变这份原局初判。出生口径沿用档案，不补造时柱或真太阳时。"
    ]
    private let details = NatalChartDetailsEngine()
    private static let elements = ["木", "火", "土", "金", "水"]

    public init() {}

    public func analyze(natal: FourPillarsChart) -> StrengthAssessmentReport {
        analyze(charts: [natal])
    }

    public func analyze(charts: [FourPillarsChart], profile: BirthProfile? = nil) -> StrengthAssessmentReport {
        var inputUncertainties: [String] = []
        if let profile {
            do {
                try profile.validate()
                if try profile.isBirthTimeAmbiguous() {
                    inputUncertainties.append("出生时刻处于当地时钟回拨的重复区间，需要先核对采用哪一次时刻。")
                }
            } catch {
                inputUncertainties.append("出生资料未通过校验：\(error.localizedDescription)")
            }
            if !profile.birthTimeKnown {
                inputUncertainties.append("出生时刻未知，时柱可能改变根气与透干，暂不定强弱。")
            }
        }
        guard let natal = charts.first else {
            return report(assessment: .unspecified, decision: "missing_chart", dayMaster: "", count: 0,
                          summary: "还没有可分析的出生盘，请先完善出生资料。", evidence: [], counter: [],
                          uncertainties: inputUncertainties + ["缺少出生四柱。"])
        }
        if charts.count > 1 {
            let variants = charts.map { [$0.year.text, $0.month.text, $0.day.text, $0.hour?.text ?? "时柱未知"].joined(separator: " · ") }.sorted()
            inputUncertainties.append("出生日期存在 \(charts.count) 组候选盘，不能把其中一组当作已经确认的命盘：\(variants.joined(separator: "；"))。")
        }
        if charts.contains(where: { $0.hour == nil }) && !inputUncertainties.contains(where: { $0.contains("时柱可能") }) {
            inputUncertainties.append("时柱未知，缺少一组透干与藏干，暂不定强弱。")
        }
        if charts.contains(where: { abs($0.instant.timeIntervalSince($0.previousJie.date)) < 600
            || abs($0.instant.timeIntervalSince($0.nextJie.date)) < 600 }) {
            inputUncertainties.append("出生记录距离交节不足 10 分钟；该窗口是产品的校盘提醒范围，需先核对时间精度与交节口径。")
        }
        // Do not choose the first candidate's evidence as if it represented the
        // entire ambiguous day. Candidate order must not affect the conclusion.
        if charts.count > 1 {
            let masters = Array(Set(charts.map { $0.day.stem + Self.elements[$0.day.stemIndex / 2] })).sorted()
            return report(assessment: .unspecified, decision: "multiple_candidates", dayMaster: masters.joined(separator: " / "), count: charts.count,
                          summary: "存在候选盘，先完成校盘，再综合月令、透干与根气判断。", evidence: [], counter: [],
                          uncertainties: inputUncertainties)
        }

        let pillars = details.details(for: natal).pillars
        let own = natal.day.stemIndex / 2
        let master = natal.day.stem + Self.elements[own]
        let monthMain = pillars[1].hiddenStems[0]
        let monthGroup = group(element: monthMain.stemIndex / 2, own: own)
        let mixedMonth = [1, 4, 7, 10].contains(natal.month.branchIndex)
        let seasonSupports = monthGroup.supports
        let visible = pillars.filter { $0.id != "day" }
        let helpers = visible.filter { group(element: $0.pillar.stemIndex / 2, own: own).supports }
        let drains = visible.filter { !group(element: $0.pillar.stemIndex / 2, own: own).supports }
        let roots = pillars.flatMap { pillar in
            pillar.hiddenStems.enumerated().compactMap { position, stem -> Root? in
                stem.stemIndex / 2 == own ? Root(pillar: pillar, stem: stem.stem, main: position == 0) : nil
            }
        }
        let mainRoots = roots.filter(\.main)
        let minorRoots = roots.filter { !$0.main }
        let branchHelpers = pillars.filter { group(element: $0.hiddenStems[0].stemIndex / 2, own: own).supports }
        let visibleObservations = visible.map { pillar in
            let matches = pillars.filter { $0.hiddenStems.contains(where: { $0.stemIndex == pillar.pillar.stemIndex }) }
            let rootText = matches.isEmpty ? "原局藏干未见同干" : "同干见于\(matches.map { $0.label + $0.pillar.branch }.joined(separator: "、"))藏干"
            return "\(pillar.label)天干\(pillar.pillar.stem)\(pillar.stemElement)为\(pillar.tenGod)，\(rootText)。"
        }
        let supportObservations = helpers.map { "\($0.label)天干\($0.pillar.stem)\($0.stemElement) · \($0.tenGod) · \(group(element: $0.pillar.stemIndex / 2, own: own).label)" }
        let drainObservations = drains.map { "\($0.label)天干\($0.pillar.stem)\($0.stemElement) · \($0.tenGod) · \(group(element: $0.pillar.stemIndex / 2, own: own).label)" }
        var evidence = [
            item("month", "月令", "出生月令", ["月柱\(natal.month.text)，月支本气\(monthMain.stem)\(monthMain.element)为\(monthMain.tenGod)，与\(master)日主呈\(monthGroup.label)关系。"],
                 "月令是提纲，但不是单独定论；本气关系不能替代整月司令与寒暖燥湿。", mixedMonth ? .mixed : (seasonSupports ? .strong : .weak)),
            item("stems", "透干", "已知天干与藏干对应", visibleObservations,
                 "日干自身不计为额外比劫；只有具体天干与藏干相同才标注对应位置。天干可见不等于有力。", .neutral),
            item("roots", "通根", "同五行根气", roots.isEmpty ? ["已知地支藏干暂未见与日主同五行的根气。"] : roots.map(\.description),
                 "本气根与其他藏干分别观察，阴阳不同仍可同五行；这里只列根气，不宣称遇冲即被消灭。", mainRoots.isEmpty ? (minorRoots.isEmpty ? .weak : .mixed) : .strong),
            item("support", "生扶", "生扶与同类", supportObservations.isEmpty ? ["除日干外，已知天干未见印比。"] : supportObservations,
                 "比劫同类相助，印星生日主；具体位置保留，不以数量相加当成旺衰分。", helpers.isEmpty ? .weak : .strong),
            item("drain", "泄耗克", "泄、耗、克分别观察", drainObservations.isEmpty ? ["除日干外，已知天干未见食伤、财星或官杀。"] : drainObservations,
                 "食伤为泄，财星为耗，官杀为克；作用路径不同，均不直接对应吉凶。", drains.isEmpty ? .neutral : .weak)
        ]
        var blockers = inputUncertainties
        if mixedMonth { blockers.append("辰戌丑未属于杂气月，v1 未细分司令、燥湿与土性作用，暂不套用普通月份初判。") }
        let structure = structuralCautions(pillars: pillars, roots: roots, dayStem: natal.day.stemIndex)
        blockers += structure
        if structure.isEmpty {
            evidence.append(item("structure", "结构复核", "本轮结构筛查", ["未检出本规则暂停判定的日干五合、完整三合三会，或月令、根气地支的六冲。"],
                                 "未检出不代表不存在特殊格局，刑害破、调候和制化仍未完整建模。", .neutral))
        } else {
            evidence.append(item("structure", "结构复核", "需要进一步复核", structure,
                                 "这里只识别关系存在，不自动断言合化成功、根气受损或格局成立。", .mixed))
        }
        // Extremes can require 从强/从弱/专旺 reasoning. Ordinary support/drain
        // criteria deliberately do not silently classify these as very strong/weak.
        if roots.isEmpty && helpers.isEmpty && branchHelpers.isEmpty {
            blockers.append("已知四柱未见日主同类根气、透干生扶或地支本气生扶，需排除从弱等特殊结构。")
        }
        if drains.isEmpty && branchHelpers.count == pillars.count {
            blockers.append("透干与地支本气均集中于印比，需排除从强、专旺等特殊结构。")
        }

        let assessment: BaziStrengthAssumption
        let decision: String
        let summary: String
        if !blockers.isEmpty {
            assessment = .unspecified
            decision = inputUncertainties.isEmpty ? "structure_review" : "input_review"
            summary = "已有月令、透干与根气线索，但存在需要复核的条件，暂不自动选定扶抑方向。"
        } else if seasonSupports && !mainRoots.isEmpty && !helpers.isEmpty && drains.count <= 1 {
            assessment = .strong
            decision = "support_aligned"
            summary = "月令本气呈生扶或同类关系，并见本气根与透干印比，普通扶抑 v1 初判偏强；仍需结合调候和制化复核。"
        } else if !seasonSupports && mainRoots.isEmpty && minorRoots.count <= 1 && drains.count >= 2 {
            assessment = .weak
            decision = "drain_aligned"
            summary = "月令本气呈泄耗克关系，未见本气根，且多处天干呈泄耗克，普通扶抑 v1 初判偏弱；已有生扶线索仍列作反证。"
        } else {
            assessment = .unspecified
            decision = "evidence_mixed"
            summary = "月令、根气与透干尚未形成一致方向，暂不强分身强或身弱；这不等于已经判为中和。"
            blockers.append("月令、根气与透干不满足 v1 的一致性条件，需要结合调候、制化与具体格局进一步判断。")
        }
        let counter: [String]
        if assessment == .strong {
            counter = drainObservations + (monthGroup == .resource ? ["月令本气为印星生扶，并非日主同类直接得令。"] : [])
        } else if assessment == .weak {
            counter = supportObservations + minorRoots.map(\.description)
        } else {
            counter = ["支持方向：\(helpers.count)处透干印比，\(mainRoots.count)处本气根，\(minorRoots.count)处其他藏干根。",
                       "另一方向：\(drains.count)处透干泄耗克，月令本气为\(monthGroup.label)。这些是位置计数，不是力量分数。"]
        }
        return report(assessment: assessment, decision: decision, dayMaster: master, count: charts.count,
                      summary: summary, evidence: evidence, counter: counter, uncertainties: blockers)
    }

    private struct Root {
        let pillar: NatalPillarDetail
        let stem: String
        let main: Bool
        var description: String { "\(pillar.label)\(pillar.pillar.text)藏\(stem)（\(main ? "本气根" : "其他藏干根")）" }
    }
    private enum Relation {
        case peer, resource, output, wealth, pressure
        var supports: Bool { self == .peer || self == .resource }
        var label: String {
            switch self {
            case .peer: return "同类相助"
            case .resource: return "印星生扶"
            case .output: return "食伤泄出"
            case .wealth: return "财星耗用"
            case .pressure: return "官杀克制"
            }
        }
    }
    private func group(element: Int, own: Int) -> Relation {
        if element == own { return .peer }
        if (element + 1) % 5 == own { return .resource }
        if (own + 1) % 5 == element { return .output }
        if (own + 2) % 5 == element { return .wealth }
        return .pressure
    }
    private func structuralCautions(pillars: [NatalPillarDetail], roots: [Root], dayStem: Int) -> [String] {
        var cautions: [String] = []
        let combines = pillars.filter { $0.id != "day" && ($0.pillar.stemIndex + 5) % 10 == dayStem }
        for pillar in combines {
            cautions.append("日干与\(pillar.label)天干\(pillar.pillar.stem)有五合关系；是否合化需要进一步判断。")
        }
        let branches = Set(pillars.map { $0.pillar.branchIndex })
        let formations: [([Int], String)] = [
            ([8, 0, 4], "申子辰三合"), ([11, 3, 7], "亥卯未三合"),
            ([2, 6, 10], "寅午戌三合"), ([5, 9, 1], "巳酉丑三合"),
            ([2, 3, 4], "寅卯辰三会"), ([5, 6, 7], "巳午未三会"),
            ([8, 9, 10], "申酉戌三会"), ([11, 0, 1], "亥子丑三会")
        ]
        for (members, name) in formations where Set(members).isSubset(of: branches) {
            cautions.append("地支见完整\(name)组合，v1 不直接判断是否成局及其改变量。")
        }
        let sensitiveIDs = Set(roots.map { $0.pillar.id } + ["month"])
        for left in pillars.indices {
            for right in pillars.indices where right > left {
                let a = pillars[left], b = pillars[right]
                if (a.pillar.branchIndex + 6) % 12 == b.pillar.branchIndex,
                   sensitiveIDs.contains(a.id) || sensitiveIDs.contains(b.id) {
                    cautions.append("\(a.label)\(a.pillar.branch)与\(b.label)\(b.pillar.branch)相冲，涉及月令或根气，需复核作用，不能直接删除根气。")
                }
            }
        }
        return cautions
    }
    private func item(_ id: String, _ category: String, _ title: String, _ observations: [String], _ note: String,
                      _ direction: StrengthEvidenceDirection) -> StrengthAssessmentEvidence {
        StrengthAssessmentEvidence(id: id, category: category, title: title, observations: observations,
                                   ruleNote: note, direction: direction)
    }
    private func report(assessment: BaziStrengthAssumption, decision: String, dayMaster: String, count: Int,
                        summary: String, evidence: [StrengthAssessmentEvidence], counter: [String],
                        uncertainties: [String]) -> StrengthAssessmentReport {
        StrengthAssessmentReport(ruleVersion: Self.ruleVersion, ruleName: Self.ruleName, decisionID: decision,
            assessment: assessment, label: assessment == .strong ? "偏强初判" : (assessment == .weak ? "偏弱初判" : "暂未确定"),
            summary: summary, dayMaster: dayMaster, candidateCount: count, evidence: evidence, counterEvidence: counter,
            uncertainties: uncertainties, scopeNote: Self.scopeNote, limitations: Self.limitations,
            sourceTitle: "灵性日历普通扶抑 v1 · 藏干依据 lunar-swift 1.1.8",
            sourceURL: NatalChartDetailsEngine.sourceURL)
    }
}
