import Foundation

/// Ordered as 甲乙丙丁戊己庚辛壬癸 and 子丑寅卯辰巳午未申酉戌亥.
/// Validation occurs at the engine boundary; no birth-date calculation is done here.
public struct BaziRelationInput: Equatable, Sendable {
    public let label: String
    public let stemIndex: Int
    public let branchIndex: Int

    public init(label: String, stemIndex: Int, branchIndex: Int) {
        self.label = label
        self.stemIndex = stemIndex
        self.branchIndex = branchIndex
    }

    public var ganZhi: String {
        guard (0..<10).contains(stemIndex), (0..<12).contains(branchIndex) else { return "未知干支" }
        return BaziRelationshipEngine.stems[stemIndex] + BaziRelationshipEngine.branches[branchIndex]
    }
}

public enum BaziTenGod: String, CaseIterable, Equatable, Sendable {
    case peer = "比肩", robWealth = "劫财", eatingGod = "食神", hurtingOfficer = "伤官"
    case indirectWealth = "偏财", directWealth = "正财", sevenKillings = "七杀", directOfficer = "正官"
    case indirectSeal = "偏印", directSeal = "正印"

    public var label: String { rawValue }
    public var reflection: String {
        switch self {
        case .peer: return "先写下自己的判断，再听一个不同意见，看看哪些部分值得调整。"
        case .robWealth: return "涉及共同使用的时间或资源时，先把分工、边界和承诺说清楚。"
        case .eatingGod: return "给今天安排一个能完成的小产出，也为吃饭和休息留出时间。"
        case .hurtingOfficer: return "把想表达的观点写成事实、感受、请求三部分，重要消息发送前再读一遍。"
        case .indirectWealth: return "面对额外邀约或新想法，先核对自己能投入多少时间，再决定是否接下。"
        case .directWealth: return "挑一件需要兑现的承诺，核对所需时间、材料和完成标准。"
        case .sevenKillings: return "把紧迫事项排出先后，预留缓冲；需要帮助时，把具体困难说出来。"
        case .directOfficer: return "开始任务前先确认要求和截止时间，做完后按清单检查一次。"
        case .indirectSeal: return "留一段时间探索不同思路，再找一项事实检验自己的猜想。"
        case .directSeal: return "整理一份能用得上的笔记，或向可信赖的人请教一个具体问题。"
        }
    }
}

public struct BaziTenGodReading: Equatable, Sendable {
    public let kind: BaziTenGod
    public let explanation: String
    public let sourceTitle: String
    public let sourceURL: String
    public var label: String { kind.label }
    public var reflection: String { kind.reflection }
}

public enum BaziRelationKind: String, CaseIterable, Equatable, Sendable {
    case stemCombination, branchCombination, branchClash, branchHarm

    public var label: String {
        switch self {
        case .stemCombination: return "天干五合"
        case .branchCombination: return "地支六合"
        case .branchClash: return "地支六冲"
        case .branchHarm: return "地支六害"
        }
    }

    public var sourceTitle: String {
        let chapter: String
        switch self {
        case .stemCombination: chapter = "论十干合"
        case .branchCombination: chapter = "论支元六合"
        case .branchClash: chapter = "论冲击"
        case .branchHarm: chapter = "论六害"
        }
        return "《三命通会》四库全书本·卷二·\(chapter)"
    }

    public var sourceURL: String { BaziRelationshipEngine.volumeTwoURL }

    public var explanation: String {
        switch self {
        case .stemCombination: return "命中传统天干五合配对。这里只记录相合，不推断已经合化，也不把合直接判为吉。"
        case .branchCombination: return "命中传统地支六合配对。相合可以作为协商与联结的反思线索，不等于事情一定顺利。"
        case .branchClash: return "两支在十二支顺序中相隔六位，属于六冲。原典也要求分别看待冲的作用，不能直接判为凶。"
        case .branchHarm: return "命中传统六害配对。本批只展示配对名称，不延伸原典中关于伤害、疾病或人际结果的断语。"
        }
    }

    public var reflection: String {
        switch self {
        case .stemCombination, .branchCombination: return "有合作事项时，明确彼此期待，再确认下一步由谁来做。"
        case .branchClash: return "看看今天哪些安排可能需要调整；给衔接紧的事项留一段缓冲。"
        case .branchHarm: return "核对约定中的默认前提，把时间、地点、分工写清楚，减少误会。"
        }
    }
}

public struct BaziRelation: Identifiable, Equatable, Sendable {
    public let kind: BaziRelationKind
    public let flowDay: BaziRelationInput
    public let pillar: BaziRelationInput
    public let pillarIndex: Int
    public let pairName: String
    public var id: String { "\(pillarIndex)-\(kind.rawValue)" }
    public var flowLabel: String { "\(flowDay.label)\(flowDay.ganZhi)" }
    public var pillarLabel: String { "\(pillar.label)\(pillar.ganZhi)" }
    public var title: String { "\(flowLabel) ↔ \(pillarLabel)：\(pairName)" }
    public var explanation: String { kind.explanation }
    public var sourceTitle: String { kind.sourceTitle }
    public var sourceURL: String { kind.sourceURL }
    public var reflection: String { kind.reflection }
}

/// Describes which pair categories occurred, never an auspiciousness ranking.
public enum BaziRelationTendency: String, Equatable, Sendable {
    case harmonizing, changing, caution, mixed, ordinary

    public var label: String {
        switch self {
        case .harmonizing: return "相合"
        case .changing: return "相冲"
        case .caution: return "相害"
        case .mixed: return "并见"
        case .ordinary: return "平和"
        }
    }
    public var reflection: String {
        switch self {
        case .harmonizing: return "把合作期待说清楚，也为自己的边界留出位置。"
        case .changing: return "给变化留出空间，提前准备一个可行的备选安排。"
        case .caution: return "重要约定再确认一次，有不确定的地方直接询问。"
        case .mixed: return "把今天的事项分别处理：能协商的先沟通，需要调整的留缓冲。"
        case .ordinary: return "按真实的精力、截止时间和现有安排，选出今天最值得完成的一件事。"
        }
    }
}

public struct BaziRelationshipReport: Equatable, Sendable {
    public let flowDay: BaziRelationInput
    public let dayMasterName: String
    public let tenGod: BaziTenGodReading
    public let relations: [BaziRelation]
    public let tendency: BaziRelationTendency
    public let checkedPillarCount: Int
    public var reflection: String { tendency.reflection }
    public var scopeNote: String { BaziRelationshipEngine.scopeNote }
    public var summary: String {
        if relations.isEmpty {
            return "已比较\(checkedPillarCount)柱，本批五合、六合、六冲、六害未命中，标记为「平和」；这不表示当天一定平顺。"
        }
        return "\(flowDay.label)\(flowDay.ganZhi)与命盘出现\(relations.count)组关系，标记为「\(tendency.label)」。这是传统关系摘要，不是吉凶结论。"
    }
}

public struct BaziRelationshipEngine: Sendable {
    public static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    public static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    public static let volumeTwoURL = "https://zh.wikisource.org/wiki/三命通會_(四庫全書本)/卷02"
    public static let volumeFiveURL = "https://zh.wikisource.org/wiki/三命通會_(四庫全書本)/卷05"
    public static let scopeNote = "仅核对流日天干相对日主的十神，以及流日与已知各柱的五合、六合、六冲、六害。不计算旺衰喜用、格局、大运、藏干、刑破、三合或合化。缺失时柱不补造。行动建议是现代自我反思提示，非古籍原文，也不承诺预测结果。"

    public enum InputError: Error, Equatable, LocalizedError {
        case invalidStem(label: String, index: Int)
        case invalidBranch(label: String, index: Int)
        case mismatchedPolarity(label: String)
        case noPillars
        public var errorDescription: String? {
            switch self {
            case .invalidStem(let label, _): return "\(label)的天干索引应为 0 至 9。"
            case .invalidBranch(let label, _): return "\(label)的地支索引应为 0 至 11。"
            case .mismatchedPolarity(let label): return "\(label)的干支阴阳不匹配，不属于六十甲子。"
            case .noPillars: return "请至少提供一个已知命盘柱位。"
            }
        }
    }

    public init() {}

    public func analyze(dayMasterStemIndex: Int, flowDay: BaziRelationInput, pillars: [BaziRelationInput]) throws -> BaziRelationshipReport {
        let tenGod = try tenGod(dayMasterStemIndex: dayMasterStemIndex, otherStemIndex: flowDay.stemIndex)
        try validate(flowDay)
        guard !pillars.isEmpty else { throw InputError.noPillars }
        var relations: [BaziRelation] = []
        for (index, pillar) in pillars.enumerated() {
            try validate(pillar)
            if Self.stemPartners[flowDay.stemIndex] == pillar.stemIndex {
                let pair = Self.canonicalPair(flowDay.stemIndex, pillar.stemIndex, names: Self.stems)
                relations.append(BaziRelation(kind: .stemCombination, flowDay: flowDay, pillar: pillar,
                                              pillarIndex: index, pairName: pair + "合"))
            }
            let branchRelations: [(BaziRelationKind, [Int], String)] = [
                (.branchCombination, Self.branchPartners, "合"),
                (.branchClash, Self.branchOpposites, "冲"),
                (.branchHarm, Self.branchHarms, "害")
            ]
            for (kind, pairs, suffix) in branchRelations where pairs[flowDay.branchIndex] == pillar.branchIndex {
                let pair = Self.canonicalPair(flowDay.branchIndex, pillar.branchIndex, names: Self.branches)
                relations.append(BaziRelation(kind: kind, flowDay: flowDay, pillar: pillar,
                                              pillarIndex: index, pairName: pair + suffix))
            }
        }
        let hasCombination = relations.contains { $0.kind == .stemCombination || $0.kind == .branchCombination }
        let hasClash = relations.contains { $0.kind == .branchClash }
        let hasHarm = relations.contains { $0.kind == .branchHarm }
        let categories = [hasCombination, hasClash, hasHarm].filter { $0 }.count
        let tendency: BaziRelationTendency = categories > 1 ? .mixed
            : hasCombination ? .harmonizing : hasClash ? .changing : hasHarm ? .caution : .ordinary
        return BaziRelationshipReport(flowDay: flowDay, dayMasterName: Self.stems[dayMasterStemIndex],
                                      tenGod: tenGod, relations: relations, tendency: tendency, checkedPillarCount: pillars.count)
    }

    public func tenGod(dayMasterStemIndex: Int, otherStemIndex: Int) throws -> BaziTenGodReading {
        try validateStem(dayMasterStemIndex, label: "日主")
        try validateStem(otherStemIndex, label: "流日")
        // Elements are ordered 木火土金水. +1 generates; +2 controls.
        let own = dayMasterStemIndex / 2, other = otherStemIndex / 2
        let samePolarity = dayMasterStemIndex % 2 == otherStemIndex % 2
        let difference = (other - own + 5) % 5
        let kind: BaziTenGod
        let relation: String
        switch difference {
        case 0: kind = samePolarity ? .peer : .robWealth; relation = "同属\(Self.elements[own])"
        case 1: kind = samePolarity ? .eatingGod : .hurtingOfficer; relation = "日主\(Self.elements[own])生流日\(Self.elements[other])"
        case 2: kind = samePolarity ? .indirectWealth : .directWealth; relation = "日主\(Self.elements[own])克流日\(Self.elements[other])"
        case 3: kind = samePolarity ? .sevenKillings : .directOfficer; relation = "流日\(Self.elements[other])克日主\(Self.elements[own])"
        default: kind = samePolarity ? .indirectSeal : .directSeal; relation = "流日\(Self.elements[other])生日主\(Self.elements[own])"
        }
        let chapter = difference == 0 ? "论阳刃" : difference == 4 ? "论印绶" : "论古人立印食官财名义"
        let explanation = "日主\(Self.stems[dayMasterStemIndex])与流日天干\(Self.stems[otherStemIndex])：\(relation)，阴阳\(samePolarity ? "相同" : "不同")，十神为\(kind.label)。十神是传统关系名称，不表示当天必然发生对应事件。"
        return BaziTenGodReading(kind: kind, explanation: explanation,
                                 sourceTitle: "《三命通会》四库全书本·卷五·\(chapter)", sourceURL: Self.volumeFiveURL)
    }

    private func validate(_ input: BaziRelationInput) throws {
        try validateStem(input.stemIndex, label: input.label)
        guard (0..<12).contains(input.branchIndex) else { throw InputError.invalidBranch(label: input.label, index: input.branchIndex) }
        guard input.stemIndex % 2 == input.branchIndex % 2 else { throw InputError.mismatchedPolarity(label: input.label) }
    }

    private func validateStem(_ index: Int, label: String) throws {
        guard (0..<10).contains(index) else { throw InputError.invalidStem(label: label, index: index) }
    }

    private static func canonicalPair(_ first: Int, _ second: Int, names: [String]) -> String {
        names[min(first, second)] + names[max(first, second)]
    }

    private static let elements = ["木", "火", "土", "金", "水"]
    private static let stemPartners = [5, 6, 7, 8, 9, 0, 1, 2, 3, 4]
    private static let branchPartners = [1, 0, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2]
    private static let branchOpposites = [6, 7, 8, 9, 10, 11, 0, 1, 2, 3, 4, 5]
    private static let branchHarms = [7, 6, 5, 4, 3, 2, 1, 0, 11, 10, 9, 8]
}
