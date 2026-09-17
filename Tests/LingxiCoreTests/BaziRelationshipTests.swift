import Foundation
import Testing
@testable import LingxiCore

struct BaziRelationshipTests {
    private let engine = BaziRelationshipEngine()

    @Test func tenGodsCoverAllHundredStemCombinations() throws {
        // Rows are day masters 甲...癸; columns are encountered stems 甲...癸.
        // Explicit fixtures avoid testing the implementation with its own formula.
        let expected = [
            ["比肩", "劫财", "食神", "伤官", "偏财", "正财", "七杀", "正官", "偏印", "正印"],
            ["劫财", "比肩", "伤官", "食神", "正财", "偏财", "正官", "七杀", "正印", "偏印"],
            ["偏印", "正印", "比肩", "劫财", "食神", "伤官", "偏财", "正财", "七杀", "正官"],
            ["正印", "偏印", "劫财", "比肩", "伤官", "食神", "正财", "偏财", "正官", "七杀"],
            ["七杀", "正官", "偏印", "正印", "比肩", "劫财", "食神", "伤官", "偏财", "正财"],
            ["正官", "七杀", "正印", "偏印", "劫财", "比肩", "伤官", "食神", "正财", "偏财"],
            ["偏财", "正财", "七杀", "正官", "偏印", "正印", "比肩", "劫财", "食神", "伤官"],
            ["正财", "偏财", "正官", "七杀", "正印", "偏印", "劫财", "比肩", "伤官", "食神"],
            ["食神", "伤官", "偏财", "正财", "七杀", "正官", "偏印", "正印", "比肩", "劫财"],
            ["伤官", "食神", "正财", "偏财", "正官", "七杀", "正印", "偏印", "劫财", "比肩"]
        ]
        for own in 0..<10 {
            for other in 0..<10 {
                let result = try engine.tenGod(dayMasterStemIndex: own, otherStemIndex: other)
                #expect(result.label == expected[own][other])
                #expect(result.explanation.contains("日主\(BaziRelationshipEngine.stems[own])"))
                #expect(result.explanation.contains("流日天干\(BaziRelationshipEngine.stems[other])"))
                #expect(!result.sourceTitle.isEmpty)
                #expect(URL(string: result.sourceURL)?.host == "zh.wikisource.org")
            }
        }
    }

    @Test func allStemCombinationsAreSymmetricAndNoOthersAreInvented() throws {
        let expected: Set<String> = ["0-5", "1-6", "2-7", "3-8", "4-9"]
        for first in 0..<10 {
            for second in 0..<10 {
                let report = try engine.analyze(dayMasterStemIndex: second,
                    flowDay: .init(label: "流日", stemIndex: first, branchIndex: first % 2),
                    pillars: [.init(label: "日柱", stemIndex: second, branchIndex: second % 2)])
                let key = "\(min(first, second))-\(max(first, second))"
                #expect(report.relations.contains { $0.kind == .stemCombination } == expected.contains(key))
            }
        }
    }

    @Test func allBranchPairsMatchOnlyTheSixCombinationsClashesAndHarms() throws {
        let combinations: Set<String> = ["0-1", "2-11", "3-10", "4-9", "5-8", "6-7"]
        let clashes: Set<String> = ["0-6", "1-7", "2-8", "3-9", "4-10", "5-11"]
        let harms: Set<String> = ["0-7", "1-6", "2-5", "3-4", "8-11", "9-10"]
        for first in 0..<12 {
            for second in 0..<12 {
                let report = try engine.analyze(dayMasterStemIndex: second % 2,
                    flowDay: .init(label: "流日", stemIndex: first % 2, branchIndex: first),
                    pillars: [.init(label: "日柱", stemIndex: second % 2, branchIndex: second)])
                let key = "\(min(first, second))-\(max(first, second))"
                #expect(report.relations.contains { $0.kind == .branchCombination } == combinations.contains(key))
                #expect(report.relations.contains { $0.kind == .branchClash } == clashes.contains(key))
                #expect(report.relations.contains { $0.kind == .branchHarm } == harms.contains(key))
            }
        }
    }

    @Test func eachFindingKeepsTheActualFlowDayAndNatalPillar() throws {
        let flow = BaziRelationInput(label: "流日", stemIndex: 0, branchIndex: 0)
        let pillars = [
            BaziRelationInput(label: "年柱", stemIndex: 5, branchIndex: 1),
            BaziRelationInput(label: "月柱", stemIndex: 2, branchIndex: 6),
            BaziRelationInput(label: "日柱", stemIndex: 1, branchIndex: 7),
            BaziRelationInput(label: "时柱", stemIndex: 4, branchIndex: 2)
        ]
        let result = try engine.analyze(dayMasterStemIndex: 1, flowDay: flow, pillars: pillars)
        #expect(result.relations.map(\.kind) == [.stemCombination, .branchCombination, .branchClash, .branchHarm])
        #expect(result.relations.map(\.pillarIndex) == [0, 0, 1, 2])
        #expect(result.relations.map(\.title) == [
            "流日甲子 ↔ 年柱己丑：甲己合", "流日甲子 ↔ 年柱己丑：子丑合",
            "流日甲子 ↔ 月柱丙午：子午冲", "流日甲子 ↔ 日柱乙未：子未害"
        ])
        #expect(Set(result.relations.map(\.id)).count == 4)
        #expect(result.tenGod.kind == .robWealth)
        #expect(result.tendency == .mixed)
        #expect(result.checkedPillarCount == 4)
        for relation in result.relations {
            #expect(relation.flowDay == flow)
            #expect(!relation.explanation.isEmpty)
            #expect(!relation.reflection.isEmpty)
            #expect(URL(string: relation.sourceURL)?.host == "zh.wikisource.org")
        }
    }

    @Test func repeatedNatalPillarsRemainDistinctAndMissingHourIsNotFabricated() throws {
        let flow = BaziRelationInput(label: "流日", stemIndex: 0, branchIndex: 0)
        let pillars = ["年柱", "月柱", "日柱"].map { BaziRelationInput(label: $0, stemIndex: 5, branchIndex: 1) }
        let result = try engine.analyze(dayMasterStemIndex: 5, flowDay: flow, pillars: pillars)
        #expect(result.relations.count == 6)
        #expect(Set(result.relations.map(\.id)).count == 6)
        #expect(result.relations.allSatisfy { $0.pillar.label != "时柱" })
        #expect(result.checkedPillarCount == 3)
        #expect(result.tendency == .harmonizing)
        #expect(result.summary.contains("不是吉凶结论"))
    }

    @Test func summariesDistinguishClashHarmAndNoMatchedPairWithoutLuckScores() throws {
        let flow = BaziRelationInput(label: "流日", stemIndex: 0, branchIndex: 0)
        let inputs: [(Int, Int, BaziRelationTendency)] = [(2, 6, .changing), (1, 7, .caution), (4, 2, .ordinary)]
        for (stem, branch, tendency) in inputs {
            let report = try engine.analyze(dayMasterStemIndex: stem, flowDay: flow,
                pillars: [.init(label: "日柱", stemIndex: stem, branchIndex: branch)])
            #expect(report.tendency == tendency)
            #expect(!report.summary.contains("%"))
            #expect(!report.reflection.isEmpty)
            #expect(report.scopeNote.contains("不承诺预测结果"))
            if tendency == .ordinary { #expect(report.summary.contains("不表示当天一定平顺")) }
        }
    }

    @Test func samePillarDoesNotInventSelfPunishmentOrHalfCombination() throws {
        for branch in [4, 6, 9, 11] {
            let input = BaziRelationInput(label: "日柱", stemIndex: branch % 2, branchIndex: branch)
            let report = try engine.analyze(dayMasterStemIndex: input.stemIndex,
                flowDay: .init(label: "流日", stemIndex: input.stemIndex, branchIndex: branch), pillars: [input])
            #expect(report.relations.isEmpty)
        }
        let partialWater = try engine.analyze(dayMasterStemIndex: 0,
            flowDay: .init(label: "流日", stemIndex: 0, branchIndex: 0),
            pillars: [.init(label: "日柱", stemIndex: 0, branchIndex: 8)])
        #expect(partialWater.relations.isEmpty)
    }

    @Test func invalidInputsFailBeforeProducingAnyReading() throws {
        let valid = BaziRelationInput(label: "日柱", stemIndex: 0, branchIndex: 0)
        #expect(throws: BaziRelationshipEngine.InputError.invalidStem(label: "日主", index: -1)) {
            try engine.analyze(dayMasterStemIndex: -1, flowDay: valid, pillars: [valid])
        }
        #expect(throws: BaziRelationshipEngine.InputError.invalidStem(label: "流日", index: 10)) {
            try engine.analyze(dayMasterStemIndex: 0, flowDay: .init(label: "流日", stemIndex: 10, branchIndex: 0), pillars: [valid])
        }
        #expect(throws: BaziRelationshipEngine.InputError.invalidBranch(label: "流日", index: 12)) {
            try engine.analyze(dayMasterStemIndex: 0, flowDay: .init(label: "流日", stemIndex: 0, branchIndex: 12), pillars: [valid])
        }
        #expect(throws: BaziRelationshipEngine.InputError.mismatchedPolarity(label: "年柱")) {
            try engine.analyze(dayMasterStemIndex: 0, flowDay: valid, pillars: [.init(label: "年柱", stemIndex: 0, branchIndex: 1)])
        }
        #expect(throws: BaziRelationshipEngine.InputError.noPillars) {
            try engine.analyze(dayMasterStemIndex: 0, flowDay: valid, pillars: [])
        }
    }
}
