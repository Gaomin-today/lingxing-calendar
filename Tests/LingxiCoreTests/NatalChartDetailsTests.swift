import Foundation
import Testing
@testable import LingxiCore

struct NatalLuckFixture: Decodable {
    let cases: [Case]
    struct Case: Decodable {
        let id, date, time, timeZone: String
        let gender: LuckGender
        let dayBoundary: BirthDayBoundary
        let details: [Detail]
        let direction: String
        let offset: [Int]
        let startAt: String
        let firstThreePillars: [String]
        var profile: BirthProfile {
            let dateParts = date.split(separator: "-").map { Int($0)! }
            let timeParts = time.split(separator: ":").map { Int($0)! }
            return BirthProfile(birthYear: dateParts[0], birthMonth: dateParts[1], birthDay: dateParts[2],
                                birthHour: timeParts[0], birthMinute: timeParts[1], birthTimeKnown: true,
                                timeZoneIdentifier: timeZone, dayBoundary: dayBoundary)
        }
    }
    struct Detail: Decodable {
        let id, pillar, tenGod, stemElement, branchElement, naYin, dayMasterStage, selfStage, xunKong: String
        let hiddenStems: [Hidden]
    }
    struct Hidden: Decodable, Equatable { let stem, element, tenGod: String }

    static func load() throws -> Self {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/natal-luck-reference.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: path))
    }
}

struct NatalChartDetailsTests {
    @Test func detailsMatchActualBaziSkillAcrossEightReferenceRecords() throws {
        let fixture = try NatalLuckFixture.load()
        #expect(fixture.cases.count == 8)
        let engine = FourPillarsEngine()
        for item in fixture.cases {
            let chart = try #require(engine.natalCharts(for: item.profile).first)
            let details = NatalChartDetailsEngine().details(for: chart)
            #expect(details.pillars.count == 4)
            for (actual, expected) in zip(details.pillars, item.details) {
                #expect(actual.id == expected.id)
                #expect(actual.pillar.text == expected.pillar)
                #expect(actual.tenGod == expected.tenGod)
                #expect(actual.stemElement == expected.stemElement)
                #expect(actual.branchElement == expected.branchElement)
                #expect(actual.naYin == expected.naYin)
                #expect(actual.dayMasterStage == expected.dayMasterStage)
                #expect(actual.selfStage == expected.selfStage)
                #expect(actual.xunKong == expected.xunKong)
                #expect(actual.hiddenStems.map { NatalLuckFixture.Hidden(stem: $0.stem, element: $0.element, tenGod: $0.tenGod) }
                        == expected.hiddenStems, "Hidden stems for \(item.id) / \(expected.id)")
            }
        }
    }

    @Test func unknownTimeDetailsKeepOnlyKnownPillarsForEveryCandidate() throws {
        let profile = BirthProfile(birthYear: 2026, birthMonth: 2, birthDay: 4)
        let charts = try FourPillarsEngine().natalCharts(for: profile)
        #expect(charts.count == 2)
        for chart in charts {
            let details = NatalChartDetailsEngine().details(for: chart)
            #expect(details.pillars.map(\.id) == ["year", "month", "day"])
            #expect(details.pillars[2].tenGod == "日主")
        }
    }

    @Test func lateZiDayBoundaryChangesDetailRelationshipsWithoutChangingHourPillar() throws {
        var profile = BirthProfile(birthYear: 1988, birthMonth: 2, birthDay: 15,
                                   birthHour: 23, birthMinute: 30, birthTimeKnown: true)
        let engine = FourPillarsEngine()
        let first = NatalChartDetailsEngine().details(for: try #require(engine.natalCharts(for: profile).first))
        profile.dayBoundary = .ziHour23
        let second = NatalChartDetailsEngine().details(for: try #require(engine.natalCharts(for: profile).first))
        #expect(first.dayMaster == "庚")
        #expect(second.dayMaster == "辛")
        #expect(first.pillars.last?.pillar == second.pillars.last?.pillar)
        #expect(first.pillars.last?.tenGod != second.pillars.last?.tenGod)
    }

    @Test func allSixtyPairsHaveValidXunAndDetailTables() {
        let engine = NatalChartDetailsEngine()
        for index in 0..<60 {
            let pair = Ganzhi(index: index)
            let detail = engine.pillarDetails(pair, dayMaster: Ganzhi(index: 0), id: "flow", label: "流年")
            #expect(detail.xun == Ganzhi(index: index / 10 * 10).text)
            #expect(detail.xunKong.count == 2)
            #expect((1...3).contains(detail.hiddenStems.count))
            #expect(!detail.naYin.isEmpty)
        }
    }
}
