import Foundation

/// A user-selected interpretive premise, never an automatically calculated score.
public enum BaziStrengthAssumption: String, Codable, CaseIterable, Identifiable, Sendable {
    case unspecified, strong, weak
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .unspecified: return "未确定"
        case .strong: return "按身强解读"
        case .weak: return "按身弱解读"
        }
    }
    public var explanation: String {
        switch self {
        case .unspecified: return "先看月令、同类与根气线索，暂不选定扶抑方向。"
        case .strong: return "采用普通扶抑法中日主偏强的假设，侧重疏导、产出与边界。"
        case .weak: return "采用普通扶抑法中日主偏弱的假设，侧重支持、准备与承接能力。"
        }
    }
}

public enum BaziReadingPeriod: String, CaseIterable, Identifiable, Sendable {
    case year, month, day
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .year: return "流年"
        case .month: return "流月"
        case .day: return "流日"
        }
    }
    public var perspective: String {
        switch self {
        case .year: return "年度回顾的视角"
        case .month: return "近期安排的视角"
        case .day: return "今天行动的视角"
        }
    }
}

public struct BaziPeriodReading: Identifiable, Equatable, Sendable {
    public let period: BaziReadingPeriod
    public let pillar: Ganzhi
    public let tenGod: BaziTenGodReading
    public let theme: String
    public let explanation: String
    public let conditionalInterpretation: String
    public let action: String
    public let ruleNote: String
    public var id: String { period.rawValue }
    public var title: String { "\(period.label)\(pillar.text) · \(tenGod.label)" }
    public var sourceTitle: String { tenGod.sourceTitle }
    public var sourceURL: String { tenGod.sourceURL }
}

/// The month branch's ordinary main qi, not an exact daily 司令 determination.
public struct BaziMonthContext: Equatable, Sendable {
    public let title: String
    public let pillar: Ganzhi
    public let mainStem: String
    public let element: String
    public let tenGod: BaziTenGodReading
    public let relationship: String
    public let summary: String
    public let ruleNote: String
    public let sourceTitle: String
    public let sourceURL: String
}

public struct BaziNatalObservation: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    /// Exact known natal locations. These entries are not weighted or scored.
    public let evidence: [String]
    public let ruleNote: String
    public let sourceTitle: String
    public let sourceURL: String
}

public struct BaziRootEvidence: Identifiable, Equatable, Sendable {
    public let pillarID: String
    public let pillarLabel: String
    public let pillar: Ganzhi
    public let hiddenStem: String
    public let isMainQi: Bool
    public var id: String { "\(pillarID)-\(hiddenStem)" }
    public var description: String {
        "\(pillarLabel)\(pillar.text)藏\(hiddenStem)（\(isMainQi ? "本气" : "其他藏干")）"
    }
}

public struct PersonalDailyReadingReport: Equatable, Sendable {
    public let dayMaster: String
    public let headline: String
    public let summary: String
    public let strength: BaziStrengthAssumption
    public let strengthContext: String
    public let natalMonth: BaziMonthContext
    public let flowMonth: BaziMonthContext
    public let observations: [BaziNatalObservation]
    public let rootEvidence: [BaziRootEvidence]
    public let periods: [BaziPeriodReading]
    public let relationships: BaziRelationshipReport
    public let actions: [String]
    public let hasUnknownBirthHour: Bool
    public let scopeNote: String
}

/// Consumes already resolved charts. It never substitutes a birth time, re-dates
/// a solar term, infers strength from counts, or calls an AI/network service.
public struct PersonalDailyReadingEngine: Sendable {
    public static let balanceSourceTitle = "《三命通会》四库全书本·卷七·子平说辩"
    public static let balanceSourceURL = "https://zh.wikisource.org/wiki/三命通會_(四庫全書本)/卷07"
    public static let hiddenStemSourceTitle = "通行藏干表 · lunar-swift 1.1.8 · LunarUtil"
    public static let hiddenStemSourceURL = "https://github.com/6tail/lunar-swift/blob/a7ec0e9b29f84a5d98b09b9ffd31145f17470d56/Sources/LunarSwift/LunarUtil.swift"
    public static let scopeNote = "这是传统规则与自我探索提示。身强、身弱是你选择的解读假设，不代表体能或心理能力。尚未综合格局、调候、合化、根气受损及大运来判断旺衰喜用；合冲不直接判吉凶，行动建议为现代转译，不承诺事件或预测结果。"

    private let relations = BaziRelationshipEngine()
    private let details = NatalChartDetailsEngine()
    private static let elements = ["木", "火", "土", "金", "水"]

    public init() {}

    public func analyze(
        natal: FourPillarsChart, flow: FourPillarsChart,
        strength: BaziStrengthAssumption = .unspecified
    ) throws -> PersonalDailyReadingReport {
        let natalDetails = details.details(for: natal)
        let ownElement = natal.day.stemIndex / 2
        let dayMaster = natal.day.stem + Self.elements[ownElement]
        let natalMonth = try monthContext(natal.month, dayMaster: natal.day, natal: true)
        let flowMonth = try monthContext(flow.month, dayMaster: natal.day, natal: false)
        let periods = try [(BaziReadingPeriod.year, flow.year), (.month, flow.month), (.day, flow.day)].map {
            try periodReading($0.0, pillar: $0.1, dayMaster: natal.day, strength: strength)
        }
        let report = try relations.analyze(dayMasterStemIndex: natal.day.stemIndex,
            flowDay: input(flow.day, label: "流日"),
            pillars: natalDetails.pillars.map { input($0.pillar, label: $0.label) })
        let peers = natalDetails.pillars.filter { $0.id != "day" && $0.pillar.stemIndex / 2 == ownElement }
            .map { "\($0.label)天干\($0.pillar.stem)\($0.stemElement)" }
        let supporters = natalDetails.pillars.filter {
            $0.id != "day" && ($0.pillar.stemIndex / 2 + 1) % 5 == ownElement
        }.map { "\($0.label)天干\($0.pillar.stem)\($0.stemElement)" }
        let roots = natalDetails.pillars.flatMap { pillar in
            pillar.hiddenStems.enumerated().compactMap { index, hidden -> BaziRootEvidence? in
                guard hidden.stemIndex / 2 == ownElement else { return nil }
                return BaziRootEvidence(pillarID: pillar.id, pillarLabel: pillar.label, pillar: pillar.pillar,
                                        hiddenStem: hidden.stem, isMainQi: index == 0)
            }
        }
        let unknown = natal.hour == nil
        let unknownSuffix = unknown ? " 出生时刻未知，时柱尚未参与。" : ""
        let observations = [
            BaziNatalObservation(id: "peers", title: "天干的同类线索",
                body: peers.isEmpty ? "已知的其他天干未见同属\(Self.elements[ownElement])的比劫。" : "其他天干有\(peers.count)处同属\(Self.elements[ownElement])，可作同类相助的线索。",
                evidence: peers, ruleNote: "日干自身不重复计入。同类出现的位置与作用仍需结合全局，数量不等于力量。" + unknownSuffix,
                sourceTitle: "《三命通会》四库全书本·卷五·十神生克", sourceURL: BaziRelationshipEngine.volumeFiveURL),
            BaziNatalObservation(id: "support", title: "天干的生扶线索",
                body: supporters.isEmpty ? "已知天干未见直接生日主的印星。地支中的生扶仍需另看。" : "\(supporters.joined(separator: "、"))生日主，可作印星生扶的线索。",
                evidence: supporters, ruleNote: "仅观察已透出的天干；见印不等于一定得到帮助，也不据此判为身强。" + unknownSuffix,
                sourceTitle: "《三命通会》四库全书本·卷五·论印绶", sourceURL: BaziRelationshipEngine.volumeFiveURL),
            BaziNatalObservation(id: "roots", title: "地支中的根气线索",
                body: roots.isEmpty ? "已知地支的通行藏干表中，暂未见日主同五行。" : "\(roots.map(\.description).joined(separator: "；"))，都含日主同五行，可作通根线索。",
                evidence: roots.map(\.description), ruleNote: "按藏干成员判断是否同五行，本气与其他藏干分别标注；不分配权重，不判断根气是否受合冲影响。未见同类不等于已经确认无根或身弱。" + unknownSuffix,
                sourceTitle: Self.hiddenStemSourceTitle, sourceURL: Self.hiddenStemSourceURL),
            BaziNatalObservation(id: "balance", title: "旺衰仍需怎样核对",
                body: "\(natalMonth.relationship)。把这条月令线索与透干、根气放在一起看，仍需核对制化与寒暖燥湿，才能进一步谈旺衰。",
                evidence: ["出生月柱\(natal.month.text)", "已知\(natalDetails.pillars.count)柱"],
                ruleNote: "本页没有自动的身强身弱结论。辰戌丑未的杂气以及交节后的司令分日均未量化。" + unknownSuffix,
                sourceTitle: Self.balanceSourceTitle, sourceURL: Self.balanceSourceURL)
        ]
        let today = periods[2]
        let strengthContext = "\(strength.label)：\(strength.explanation)" + (unknown ? " 出生时刻未知，目前仅观察三柱。" : "")
        let summary = "以\(dayMaster)日元为参照，流日\(flow.day.text)的\(flow.day.stem)为\(today.tenGod.label)。\(today.conditionalInterpretation)"
        var actions = [today.action, conditionalAction(kind: today.tenGod.kind, strength: strength)]
        actions.append(report.reflection)
        var seen = Set<String>()
        actions = actions.filter { seen.insert($0).inserted }
        return PersonalDailyReadingReport(dayMaster: dayMaster,
            headline: "今日主题 · \(today.theme)", summary: summary, strength: strength,
            strengthContext: strengthContext, natalMonth: natalMonth, flowMonth: flowMonth,
            observations: observations, rootEvidence: roots, periods: periods, relationships: report,
            actions: actions, hasUnknownBirthHour: unknown, scopeNote: Self.scopeNote)
    }

    private func input(_ pair: Ganzhi, label: String) -> BaziRelationInput {
        BaziRelationInput(label: label, stemIndex: pair.stemIndex, branchIndex: pair.branchIndex)
    }

    private func monthContext(_ month: Ganzhi, dayMaster: Ganzhi, natal: Bool) throws -> BaziMonthContext {
        let hidden = details.pillarDetails(month, dayMaster: dayMaster, id: "month", label: "月柱").hiddenStems
        // The shared, version-pinned table contains at least one hidden stem for every branch.
        let main = hidden[0]
        let tenGod = try reading(dayMaster: dayMaster, otherStem: main.stemIndex, subject: "月支\(month.branch)的本气\(main.stem)")
        let own = dayMaster.stemIndex / 2
        let relation = relationPhrase(ownElement: own, otherElement: main.stemIndex / 2)
        let relationship: String
        switch group(tenGod.kind) {
        case .peer: relationship = "月支本气与日主同五行，可作得令的一条线索"
        case .support: relationship = "月支本气生日主，可作月令生扶的一条线索"
        case .output: relationship = "日主生月支本气，月令呈食伤泄出的关系"
        case .wealth: relationship = "日主克月支本气，月令呈财星耗用的关系"
        case .pressure: relationship = "月支本气克日主，月令呈官杀约束的关系"
        }
        let opening = natal ? "出生月柱为\(month.text)" : "参考时刻的流月为\(month.text)"
        let remaining = hidden.dropFirst().map(\.stem).joined(separator: "、")
        return BaziMonthContext(title: natal ? "出生月令" : "当下月气", pillar: month, mainStem: main.stem,
            element: main.element, tenGod: tenGod, relationship: relationship,
            summary: "\(opening)，月支\(month.branch)先按本气\(main.stem)\(main.element)观察；\(relation)，相对日主为\(tenGod.label)。",
            ruleNote: "月令来自节气月，不是公历月份或农历初一。这里用通行藏干表的本气作简化观察，不把整个月都视为同一司令；其他藏干为\(remaining.isEmpty ? "无" : remaining)。单看本气不能定旺衰或喜用。",
            sourceTitle: Self.hiddenStemSourceTitle, sourceURL: Self.hiddenStemSourceURL)
    }

    private func reading(dayMaster: Ganzhi, otherStem: Int, subject: String) throws -> BaziTenGodReading {
        let base = try relations.tenGod(dayMasterStemIndex: dayMaster.stemIndex, otherStemIndex: otherStem)
        let relation = relationPhrase(ownElement: dayMaster.stemIndex / 2, otherElement: otherStem / 2)
        let polarity = dayMaster.stemIndex % 2 == otherStem % 2 ? "阴阳相同" : "阴阳相异"
        return BaziTenGodReading(kind: base.kind,
            explanation: "日主\(dayMaster.stem)\(Self.elements[dayMaster.stemIndex / 2])与\(subject)：\(relation)，\(polarity)，按十神规则记为\(base.label)。",
            sourceTitle: base.sourceTitle, sourceURL: base.sourceURL)
    }

    private func periodReading(_ period: BaziReadingPeriod, pillar: Ganzhi, dayMaster: Ganzhi, strength: BaziStrengthAssumption) throws -> BaziPeriodReading {
        let tenGod = try reading(dayMaster: dayMaster, otherStem: pillar.stemIndex, subject: "\(period.label)天干\(pillar.stem)")
        let theme = theme(tenGod.kind)
        return BaziPeriodReading(period: period, pillar: pillar, tenGod: tenGod, theme: theme,
            explanation: "\(tenGod.explanation)把它用作\(period.perspective)，可以围绕「\(theme)」检查自己的安排。",
            conditionalInterpretation: conditionalInterpretation(kind: tenGod.kind, strength: strength),
            action: tenGod.reflection,
            ruleNote: "十神只取本层天干相对出生日干的生克与阴阳；年、月、日分别呈现，不合并成吉凶分。主题与行动是现代转译，扶抑提示采用用户所选假设，未据此判定喜用神。")
    }

    private enum Group { case peer, support, output, wealth, pressure }
    private func group(_ kind: BaziTenGod) -> Group {
        switch kind {
        case .peer, .robWealth: return .peer
        case .directSeal, .indirectSeal: return .support
        case .eatingGod, .hurtingOfficer: return .output
        case .directWealth, .indirectWealth: return .wealth
        case .directOfficer, .sevenKillings: return .pressure
        }
    }

    private func relationPhrase(ownElement: Int, otherElement: Int) -> String {
        let own = Self.elements[ownElement], other = Self.elements[otherElement]
        if ownElement == otherElement { return "\(own)与\(other)同类" }
        if (otherElement + 1) % 5 == ownElement { return "\(other)生\(own)" }
        if (ownElement + 1) % 5 == otherElement { return "\(own)生\(other)" }
        if (ownElement + 2) % 5 == otherElement { return "\(own)克\(other)" }
        return "\(other)克\(own)"
    }

    private func theme(_ kind: BaziTenGod) -> String {
        switch kind {
        case .peer: return "自主与协作"
        case .robWealth: return "分工与资源边界"
        case .eatingGod: return "稳定产出与生活节奏"
        case .hurtingOfficer: return "表达与改进"
        case .indirectWealth: return "机会筛选与投入"
        case .directWealth: return "兑现与资源管理"
        case .sevenKillings: return "优先级与压力应对"
        case .directOfficer: return "规则与责任"
        case .indirectSeal: return "探索与核实"
        case .directSeal: return "学习与支持"
        }
    }

    private func conditionalInterpretation(kind: BaziTenGod, strength: BaziStrengthAssumption) -> String {
        if strength == .unspecified {
            return "强弱尚未确定，先把「\(theme(kind))」当作反思主题，按实际安排选择行动。"
        }
        let content: String
        switch (strength, group(kind)) {
        case (.strong, .peer): content = "同类再来，普通扶抑法会关注助力是否过多；可反思自主与协作的分寸。"
        case (.weak, .peer): content = "同类可作扶助线索；可反思哪些任务值得与人分担。"
        case (.strong, .support): content = "生扶再来，普通扶抑法会关注是否停留在积累；可反思怎样把所学用于产出。"
        case (.weak, .support): content = "印星可作生扶线索；可反思准备、学习和求助是否到位。"
        case (.strong, .output): content = "食伤可作疏导日主的线索；可反思如何把想法变成清楚、可交付的成果。"
        case (.weak, .output): content = "食伤有泄出的一面；可反思表达和产出是否超出当前可投入的时间。"
        case (.strong, .wealth): content = "财星可作耗用日主的线索；可反思怎样让投入对应明确目标，而不是不断加码。"
        case (.weak, .wealth): content = "财星有耗用的一面；可先反思现有承诺与资源是否匹配。"
        case (.strong, .pressure): content = "官杀可作约束日主的线索；可反思怎样用规则帮助自己聚焦。"
        case (.weak, .pressure): content = "官杀有克制的一面；可反思要求是否清楚、是否需要拆分责任。"
        default: content = "先依据真实安排选择行动。"
        }
        return "若\(strength == .strong ? "身强" : "身弱")假设成立，\(content)"
    }

    private func conditionalAction(kind: BaziTenGod, strength: BaziStrengthAssumption) -> String {
        switch (strength, group(kind)) {
        case (.strong, .peer): return "开始协作前，写清自己负责什么、哪些决定需要共同确认。"
        case (.weak, .peer): return "选一个适合协作的环节，请对方提供明确、有限的支持。"
        case (.strong, .support): return "给资料搜集设一个截止点，然后交付一份可以讨论的初稿。"
        case (.weak, .support): return "在重要事项前留出准备时间，确认材料和可请教的人。"
        case (.strong, .output): return "把一个待办改写成可验收的产出，并安排一段专注时间。"
        case (.weak, .output): return "把产出拆成最小可完成的一步，完成后再决定是否追加。"
        case (.strong, .wealth): return "为一个目标同时写下投入上限与完成标准，再安排时间。"
        case (.weak, .wealth): return "接新安排前先查看日历负荷，必要时协商范围或截止时间。"
        case (.strong, .pressure): return "选一条真正有用的验收标准，用它检查当前最重要的任务。"
        case (.weak, .pressure): return "把紧迫要求分成必须、可协商、可求助三类，先处理必须项。"
        default: return "先确认自己的真实时间与精力，再挑一项建议放进今天的日历。"
        }
    }
}
