import Foundation
import Testing
@testable import LingxiCore

struct PersonalDailyReadingTests {
    private let engine = PersonalDailyReadingEngine()

    private func chart(year: Int = 9, month: Int = 50, day: Int = 0, hour: Int? = 2) -> FourPillarsChart {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        return FourPillarsChart(instant: instant, year: Ganzhi(index: year), month: Ganzhi(index: month),
            day: Ganzhi(index: day), hour: hour.map { Ganzhi(index: $0) }, timeZoneIdentifier: "Asia/Shanghai",
            dayBoundary: .midnight, previousJie: .init(index: 20, date: instant.addingTimeInterval(-10_000)),
            nextJie: .init(index: 22, date: instant.addingTimeInterval(20_000)))
    }

    @Test func periodsUseEachSuppliedPillarAndTheNatalDayMaster() throws {
        let flow = chart(year: 42, month: 33, day: 25)
        let result = try engine.analyze(natal: chart(), flow: flow)
        #expect(result.dayMaster == "甲木")
        #expect(result.periods.map(\.period) == [.year, .month, .day])
        #expect(result.periods.map(\.pillar) == [flow.year, flow.month, flow.day])
        #expect(result.periods.map(\.tenGod.kind) == [.eatingGod, .hurtingOfficer, .directWealth])
        #expect(result.periods[0].explanation.contains("流年天干丙"))
        #expect(!result.periods[0].explanation.contains("流日"))
        #expect(result.periods[1].explanation.contains("流月天干丁"))
        #expect(result.periods[2].explanation.contains("流日天干己"))
        #expect(result.natalMonth.pillar == Ganzhi(index: 50))
        #expect(result.flowMonth.pillar == flow.month)
        #expect(result.flowMonth.mainStem == "辛")
        #expect(result.flowMonth.tenGod.kind == .directOfficer)
        #expect(result.flowMonth.tenGod.kind != result.periods[1].tenGod.kind)
    }

    @Test func allMonthBranchesExposeMainQiWithoutTreatingThemAsDailyCommand() throws {
        let stems = ["癸", "己", "甲", "乙", "戊", "丙", "丁", "己", "庚", "辛", "戊", "壬"]
        let elements = ["水", "土", "木", "木", "土", "火", "火", "土", "金", "金", "土", "水"]
        let gods: [BaziTenGod] = [.directSeal, .directWealth, .peer, .robWealth, .indirectWealth,
            .eatingGod, .hurtingOfficer, .directWealth, .sevenKillings, .directOfficer, .indirectWealth, .indirectSeal]
        for branch in 0..<12 {
            let result = try engine.analyze(natal: chart(month: branch), flow: chart(month: branch))
            #expect(result.natalMonth.mainStem == stems[branch])
            #expect(result.natalMonth.element == elements[branch])
            #expect(result.natalMonth.tenGod.kind == gods[branch])
            #expect(result.natalMonth.ruleNote.contains("不把整个月都视为同一司令"))
            #expect(result.natalMonth.ruleNote.contains("单看本气不能定旺衰"))
        }
    }

    @Test func evidencePreservesLocationsAndExcludesTheDayMasterFromPeerCounts() throws {
        let result = try engine.analyze(natal: chart(), flow: chart())
        let peers = try #require(result.observations.first { $0.id == "peers" })
        let support = try #require(result.observations.first { $0.id == "support" })
        #expect(peers.evidence == ["月柱天干甲木"])
        #expect(support.evidence == ["年柱天干癸水"])
        #expect(result.rootEvidence.map(\.pillarID) == ["month", "hour"])
        #expect(result.rootEvidence.map(\.hiddenStem) == ["甲", "甲"])
        #expect(result.rootEvidence.allSatisfy { $0.isMainQi })
        #expect(Set(result.rootEvidence.map(\.id)).count == result.rootEvidence.count)
    }

    @Test func rootsUseSameElementIncludingOtherPolarityAndMarkNonMainQi() throws {
        // 甲 sees 乙 in 辰 and 未, despite opposite stem polarity.
        let result = try engine.analyze(natal: chart(year: 40, month: 43, day: 0, hour: nil), flow: chart())
        #expect(result.rootEvidence.map(\.hiddenStem) == ["乙", "乙"])
        #expect(result.rootEvidence.allSatisfy { !$0.isMainQi })
        #expect(result.rootEvidence.map(\.pillarID) == ["year", "month"])
    }

    @Test func unknownHourOmitsItsRootsAndDoesNotAssertWeaknessOrNoRoots() throws {
        let known = try engine.analyze(natal: chart(year: 56, month: 57, day: 30, hour: 38), flow: chart())
        let unknown = try engine.analyze(natal: chart(year: 56, month: 57, day: 30, hour: nil), flow: chart())
        #expect(known.rootEvidence.map(\.pillarID) == ["hour"])
        #expect(unknown.rootEvidence.isEmpty)
        #expect(unknown.hasUnknownBirthHour)
        #expect(unknown.strength == .unspecified)
        #expect(unknown.strengthContext.contains("三柱"))
        #expect(unknown.relationships.checkedPillarCount == 3)
        #expect(unknown.relationships.relations.allSatisfy { $0.pillar.label != "时柱" })
        let roots = try #require(unknown.observations.first { $0.id == "roots" })
        #expect(roots.body.contains("暂未见"))
        #expect(roots.ruleNote.contains("未见同类不等于已经确认无根或身弱"))
    }

    @Test func strengthAssumptionChangesOnlyConditionalReadingAndActions() throws {
        for stem in 0..<10 {
            let flow = chart(day: stem)
            let unspecified = try engine.analyze(natal: chart(), flow: flow)
            let strong = try engine.analyze(natal: chart(), flow: flow, strength: .strong)
            let weak = try engine.analyze(natal: chart(), flow: flow, strength: .weak)
            #expect(strong.observations == weak.observations)
            #expect(strong.rootEvidence == weak.rootEvidence)
            #expect(strong.relationships == weak.relationships)
            #expect(strong.natalMonth == weak.natalMonth)
            #expect(strong.periods.map(\.tenGod) == weak.periods.map(\.tenGod))
            #expect(strong.summary.contains("若身强假设成立"))
            #expect(weak.summary.contains("若身弱假设成立"))
            #expect(unspecified.summary.contains("强弱尚未确定"))
            #expect(strong.actions != weak.actions)
            #expect(!strong.summary.contains("%"))
            #expect(!weak.summary.contains("%"))
        }
    }

    @Test func dailyRelationshipsStillNameTheActualNatalPillars() throws {
        let result = try engine.analyze(natal: chart(), flow: chart(day: 25)) // 己丑
        let titles = result.relationships.relations.map(\.title)
        #expect(titles.contains("流日己丑 ↔ 月柱甲寅：甲己合"))
        #expect(titles.contains("流日己丑 ↔ 日柱甲子：甲己合"))
        #expect(titles.contains("流日己丑 ↔ 日柱甲子：子丑合"))
        #expect(result.scopeNote.contains("合冲不直接判吉凶"))
        #expect(result.scopeNote.contains("大运"))
    }

    @Test func selectedAssumptionsRoundTripAndEveryEvidenceHasARealSource() throws {
        for assumption in BaziStrengthAssumption.allCases {
            let data = try JSONEncoder().encode(assumption)
            #expect(try JSONDecoder().decode(BaziStrengthAssumption.self, from: data) == assumption)
            #expect(!assumption.label.isEmpty && !assumption.explanation.isEmpty)
        }
        let result = try engine.analyze(natal: chart(), flow: chart())
        let sources = result.observations.map(\.sourceURL) + result.periods.map(\.sourceURL)
            + [result.natalMonth.sourceURL, result.flowMonth.sourceURL]
        #expect(sources.allSatisfy { URL(string: $0)?.scheme == "https" })
        #expect(sources.allSatisfy { ["zh.wikisource.org", "github.com"].contains(URL(string: $0)?.host ?? "") })
        #expect(result.actions.count >= 2)
        #expect(result.actions.allSatisfy { !$0.isEmpty })
    }
}
