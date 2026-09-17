import Foundation
import Testing
@testable import LingxiCore

struct StrengthAssessmentTests {
    private let engine = StrengthAssessmentEngine()

    /// Synthetic structures test the published decision boundary, not claims
    /// about the fate or characteristics of any real individual.
    private func chart(year: Int = 59, month: Int = 50, day: Int = 0, hour: Int? = 2,
                       nearJie: Bool = false) -> FourPillarsChart {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        return FourPillarsChart(instant: instant, year: Ganzhi(index: year), month: Ganzhi(index: month),
            day: Ganzhi(index: day), hour: hour.map { Ganzhi(index: $0) }, timeZoneIdentifier: "Asia/Shanghai",
            dayBoundary: .midnight, previousJie: .init(index: 20, date: instant.addingTimeInterval(nearJie ? -599 : -10_000)),
            nextJie: .init(index: 22, date: instant.addingTimeInterval(20_000)))
    }

    @Test func alignedEvidenceProducesAnExplicitVersionedStrongTendency() throws {
        let report = engine.analyze(natal: chart())
        #expect(report.assessment == .strong)
        #expect(report.label == "偏强初判")
        #expect(report.ruleVersion == "ordinary-fuyi-v1.0")
        #expect(report.decisionID == "support_aligned")
        #expect(report.dayMaster == "甲木")
        #expect(report.uncertainties.isEmpty)
        #expect(report.evidence.map(\.id) == ["month", "stems", "roots", "support", "drain", "structure"])
        #expect(report.counterEvidence.contains { $0.contains("时柱天干丙火") && $0.contains("食伤泄出") })
        let roots = try #require(report.evidence.first { $0.id == "roots" })
        #expect(roots.observations == ["年柱癸亥藏甲（其他藏干根）", "月柱甲寅藏甲（本气根）", "时柱丙寅藏甲（本气根）"])
        #expect(report.scopeNote.contains("不代表体能、心理能力"))
    }

    @Test func weakEvidenceRetainsItsSupportingCounterEvidence() throws {
        let report = engine.analyze(natal: chart(year: 42, month: 57, hour: 8)) // 丙午 辛酉 甲子 壬申
        #expect(report.assessment == .weak)
        #expect(report.decisionID == "drain_aligned")
        #expect(report.counterEvidence.contains { $0.contains("壬水") && $0.contains("印星生扶") })
        let drain = try #require(report.evidence.first { $0.id == "drain" })
        #expect(drain.observations.contains { $0.contains("食伤泄出") })
        #expect(drain.observations.contains { $0.contains("官杀克制") })
        #expect(!report.summary.contains("无生扶"))
    }

    @Test func monthAloneDoesNotOverrideOpposingVisibleStructure() {
        let report = engine.analyze(natal: chart(year: 12, month: 26, hour: 54)) // 丙子 庚寅 甲子 戊午
        #expect(report.assessment == .unspecified)
        #expect(report.decisionID == "evidence_mixed")
        #expect(report.summary.contains("不等于已经判为中和"))
        #expect(report.evidence.first { $0.id == "month" }?.direction == .strong)
        #expect(report.evidence.first { $0.id == "support" }?.direction == .weak)
    }

    @Test func identicalElementCountsDoNotEraseTheMonthPosition() {
        let spring = engine.analyze(natal: chart(year: 57, month: 50, hour: 38))
        let autumn = engine.analyze(natal: chart(year: 50, month: 57, hour: 38))
        // Identical four pillars in a different year/month order have identical
        // stem/branch quantities, yet different seasonal evidence.
        #expect(spring.assessment == .strong)
        #expect(autumn.assessment == .unspecified)
        #expect(spring.evidence.first { $0.id == "month" }?.direction == .strong)
        #expect(autumn.evidence.first { $0.id == "month" }?.direction == .weak)
    }

    @Test func unknownHourNeverBorrowsARepresentativeHourOrDeclaresWeakness() {
        let report = engine.analyze(natal: chart(hour: nil))
        #expect(report.assessment == .unspecified)
        #expect(report.decisionID == "input_review")
        #expect(report.uncertainties.contains { $0.contains("时柱未知") })
        #expect(report.evidence.flatMap(\.observations).allSatisfy { !$0.contains("时柱") })
        #expect(report.evidence.first { $0.id == "support" }?.observations.count == 2)
    }

    @Test func multipleCandidatesDoNotExposeAnArbitraryFirstVerdict() {
        let strong = chart()
        let weak = chart(year: 42, month: 57, day: 1, hour: nil, nearJie: true)
        let result = engine.analyze(charts: [strong, weak])
        #expect(result.assessment == .unspecified)
        #expect(result.decisionID == "multiple_candidates")
        #expect(result.candidateCount == 2)
        #expect(result.evidence.isEmpty)
        #expect(result == engine.analyze(charts: [weak, strong]))
    }

    @Test func oppositePolarityRootsAreRetainedAndMinorRootsRemainCounterEvidence() throws {
        let report = engine.analyze(natal: chart(year: 42, month: 57, hour: 28)) // 壬辰藏乙
        #expect(report.assessment == .weak)
        #expect(report.counterEvidence.contains("时柱壬辰藏乙（其他藏干根）"))
        let roots = try #require(report.evidence.first { $0.id == "roots" })
        #expect(roots.direction == .mixed)
        #expect(roots.observations == ["时柱壬辰藏乙（其他藏干根）"])
    }

    @Test func dayMasterIsNotCountedAsAnExtraVisibleHelperAndExposedStemsAreSpecific() throws {
        let report = engine.analyze(natal: chart())
        let stems = try #require(report.evidence.first { $0.id == "stems" })
        let support = try #require(report.evidence.first { $0.id == "support" })
        #expect(stems.observations.count == 3)
        #expect(support.observations.count == 2)
        #expect(stems.observations.allSatisfy { !$0.hasPrefix("日柱天干") })
        #expect(stems.observations.contains { $0.contains("年柱天干癸水") && $0.contains("同干见于日柱子藏干") })
        #expect(stems.observations.contains { $0.contains("月柱天干甲木") && $0.contains("年柱亥、月柱寅、时柱寅") })
    }

    @Test func mixedEarthMonthsAreExplicitlyOutsideTheInitialClassifier() {
        for branch in [1, 4, 7, 10] {
            let report = engine.analyze(natal: chart(month: branch))
            #expect(report.assessment == .unspecified)
            #expect(report.uncertainties.contains { $0.contains("杂气月") })
        }
    }

    @Test func importantCombinationsAndRootClashesPauseWithoutInventingTransformation() throws {
        let dayCombination = engine.analyze(natal: chart(year: 35)) // 己亥
        #expect(dayCombination.assessment == .unspecified)
        #expect(dayCombination.uncertainties.contains { $0.contains("五合") })
        let completeFormation = engine.analyze(natal: chart(year: 58, day: 30, hour: 22)) // 寅午戌
        #expect(completeFormation.assessment == .unspecified)
        #expect(completeFormation.uncertainties.contains { $0.contains("寅午戌三合") })
        let rootClash = engine.analyze(natal: chart(year: 8)) // 申冲寅
        #expect(rootClash.assessment == .unspecified)
        #expect(rootClash.uncertainties.contains { $0.contains("相冲") && $0.contains("不能直接删除根气") })
        let roots = try #require(rootClash.evidence.first { $0.id == "roots" })
        #expect(roots.observations.count == 2) // Root facts survive the caution.
    }

    @Test func extremeStructuresAreNotSilentlyClassifiedByAnOrdinaryRule() {
        let noSupport = engine.analyze(natal: chart(year: 42, month: 57, day: 30, hour: 18)) // 丙午 辛酉 甲午 壬午 (replace 壬 below)
        // This version has 壬 support; removing it changes the applicability, not
        // merely a numerical total. 戊午 has no natal roots or resources.
        let unsupported = engine.analyze(natal: chart(year: 42, month: 57, day: 30, hour: 54))
        #expect(noSupport.assessment == .weak)
        #expect(unsupported.assessment == .unspecified)
        #expect(unsupported.uncertainties.contains { $0.contains("从弱") })
        let allSupport = engine.analyze(natal: chart(year: 59, month: 50, hour: 50))
        #expect(allSupport.assessment == .unspecified)
        #expect(allSupport.uncertainties.contains { $0.contains("从强") })
    }

    @Test func nearJieAndInvalidOrAmbiguousProfilesRequireInputReview() {
        #expect(engine.analyze(natal: chart(nearJie: true)).uncertainties.contains { $0.contains("10 分钟") })
        let invalid = BirthProfile(birthYear: 2000, birthMonth: 2, birthDay: 30, birthTimeKnown: true)
        let result = engine.analyze(charts: [chart()], profile: invalid)
        #expect(result.assessment == .unspecified)
        #expect(result.uncertainties.contains { $0.contains("校验") })
        let ambiguous = BirthProfile(birthYear: 2020, birthMonth: 11, birthDay: 1, birthHour: 1,
                                     birthMinute: 30, birthTimeKnown: true, timeZoneIdentifier: "America/New_York")
        #expect(engine.analyze(charts: [chart()], profile: ambiguous).uncertainties.contains { $0.contains("重复区间") })
    }

    @Test func metadataAndManualPremisesCannotChangeTheAutomaticNatalReport() throws {
        var profile = BirthProfile(name: "合成甲", birthTimeKnown: true, strengthAssumption: .strong)
        let first = engine.analyze(charts: [chart()], profile: profile)
        profile.name = "合成乙"
        profile.birthplace = "只用于显示的地址"
        profile.luckGender = .female
        profile.strengthAssumption = .weak
        #expect(engine.analyze(charts: [chart()], profile: profile) == first)
        let json = try JSONEncoder().encode(first)
        #expect(try JSONDecoder().decode(StrengthAssessmentReport.self, from: json) == first)
        let fields = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(fields["score"] == nil && fields["confidence"] == nil && fields["favorableElements"] == nil)
    }

    @Test func emptyInputIsAnExplicitRecoverableState() {
        let result = engine.analyze(charts: [])
        #expect(result.assessment == .unspecified)
        #expect(result.decisionID == "missing_chart")
        #expect(result.evidence.isEmpty)
        #expect(result.candidateCount == 0)
    }
}
