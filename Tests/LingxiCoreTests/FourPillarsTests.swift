import Foundation
import Testing
@testable import LingxiCore

struct FourPillarsTests {
    /// Deliberately synthetic boundaries isolate civil-time/uncertainty logic.
    /// They are not astronomical reference data: terms occur on the 6th/21st.
    private static func syntheticTerms(year: Int) -> [SolarTermBoundary] {
        (0..<24).map { index in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = FourPillarsEngine.defaultTimeZone
            let date = calendar.date(from: DateComponents(
                year: year, month: index / 2 + 1, day: index.isMultiple(of: 2) ? 6 : 21, hour: 12
            ))!
            return SolarTermBoundary(index: index, date: date)
        }
    }

    private var engine: FourPillarsEngine {
        FourPillarsEngine(solarTermsProvider: { Self.syntheticTerms(year: $0) })
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func ganzhiCycleRemainsValidAndRejectsInvalidDecodedIndex() throws {
        #expect(Ganzhi(index: 0).text == "甲子")
        #expect(Ganzhi(index: -1).text == "癸亥")
        #expect(Ganzhi(index: 60).text == "甲子")
        #expect(try JSONDecoder().decode(Ganzhi.self, from: JSONEncoder().encode(Ganzhi(index: 59))).text == "癸亥")
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Ganzhi.self, from: Data("60".utf8)) }
    }

    @Test func knownBirthTimeReturnsOneFourPillarChart() throws {
        let profile = BirthProfile(birthYear: 2005, birthMonth: 12, birthDay: 23,
                                   birthHour: 8, birthMinute: 37, birthTimeKnown: true)
        let charts = try engine.natalCharts(for: profile)
        #expect(charts.count == 1)
        #expect(charts[0].instant == (try profile.resolvedBirthDate()))
        // This non-boundary date also matches lunar-swift's published EightCharTests.test1.
        #expect([charts[0].year.text, charts[0].month.text, charts[0].day.text, charts[0].hour?.text] == ["乙酉", "戊子", "辛巳", "壬辰"])
    }

    @Test func unknownTimeOnOrdinaryDayReturnsOneCandidateWithoutHour() throws {
        let profile = BirthProfile(birthYear: 2026, birthMonth: 9, birthDay: 17)
        let charts = try engine.natalCharts(for: profile)
        #expect(charts.count == 1)
        #expect(charts[0].hour == nil)
        #expect(charts[0].previousJie.name == "白露")
        #expect(charts[0].nextJie.name == "寒露")
    }

    @Test func unknownLichunDayKeepsBothYearAndMonthCandidates() throws {
        let profile = BirthProfile(birthYear: 2026, birthMonth: 2, birthDay: 6)
        let charts = try engine.natalCharts(for: profile)
        #expect(charts.count == 2)
        #expect(charts.map(\.year.text) == ["乙巳", "丙午"])
        #expect(charts.map(\.month.text) == ["己丑", "庚寅"])
        #expect(charts[0].day == charts[1].day)
        #expect(charts.allSatisfy { $0.hour == nil })
    }

    @Test func unknownZiBoundaryDayProducesTwoOrThreeCandidates() throws {
        let normal = BirthProfile(birthYear: 2026, birthMonth: 9, birthDay: 17, dayBoundary: .ziHour23)
        let normalCharts = try engine.natalCharts(for: normal)
        #expect(normalCharts.count == 2)
        #expect(normalCharts[1].day == Ganzhi(index: normalCharts[0].day.index + 1))
        let transition = BirthProfile(birthYear: 2026, birthMonth: 2, birthDay: 6, dayBoundary: .ziHour23)
        let transitionCharts = try engine.natalCharts(for: transition)
        #expect(transitionCharts.count == 3)
        #expect(transitionCharts[0].year != transitionCharts[1].year)
        #expect(transitionCharts[1].year == transitionCharts[2].year)
        #expect(transitionCharts[1].day != transitionCharts[2].day)
        #expect((normalCharts + transitionCharts).allSatisfy { $0.hour == nil })
    }

    @Test func simultaneousJieAndZiCutDoesNotInventExtraCandidate() throws {
        let engine = FourPillarsEngine(solarTermsProvider: { year in
            Self.syntheticTerms(year: year).map { term in
                SolarTermBoundary(index: term.index, date: term.index == 2 ? term.date.addingTimeInterval(11 * 3600) : term.date)
            }
        })
        let profile = BirthProfile(birthYear: 2026, birthMonth: 2, birthDay: 6, dayBoundary: .ziHour23)
        let charts = try engine.natalCharts(for: profile)
        #expect(charts.count == 2)
        #expect(charts[0].year != charts[1].year)
        #expect(charts[0].day != charts[1].day)
    }

    @Test func majorQiDoesNotSplitMonthCandidate() throws {
        let profile = BirthProfile(birthYear: 2026, birthMonth: 2, birthDay: 21)
        let charts = try engine.natalCharts(for: profile)
        #expect(charts.count == 1)
        #expect(charts[0].month.text == "庚寅")
    }

    @Test func termBoundaryBelongsToNewYearAndMonthAtTheExactInstant() throws {
        let lichun = try #require(engine.solarTerms(in: 2026).first { $0.name == "立春" })
        let before = try engine.chart(at: lichun.date.addingTimeInterval(-0.01))
        let at = try engine.chart(at: lichun.date)
        #expect(before.year.text == "乙巳")
        #expect(at.year.text == "丙午")
        #expect(at.previousJie == lichun)
        #expect(before.nextJie == lichun)
    }

    @Test func dayAndLateZiPoliciesAreExplicit() throws {
        let late = date("1988-02-15T23:30:00+08:00")
        let midnight = try engine.chart(at: late, dayBoundary: .midnight)
        let zi = try engine.chart(at: late, dayBoundary: .ziHour23)
        #expect(midnight.day.text == "庚子")
        #expect(zi.day.text == "辛丑")
        #expect(midnight.hour?.text == "戊子")
        #expect(zi.hour == midnight.hour)
    }

    @Test func unknownCivilDateHandlesMidnightDSTGapAndRejectsSkippedDate() throws {
        let profile = BirthProfile(birthYear: 2019, birthMonth: 9, birthDay: 8, timeZoneIdentifier: "America/Santiago")
        let charts = try engine.natalCharts(for: profile)
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try profile.validatedTimeZone()
        let start = local.startOfDay(for: try profile.referenceBirthDate())
        #expect(local.component(.hour, from: start) == 1)
        #expect(charts.count == 1)
        #expect(charts[0].hour == nil)
        #expect(local.isDate(charts[0].instant, inSameDayAs: start))
        let skipped = BirthProfile(birthYear: 2011, birthMonth: 12, birthDay: 30, timeZoneIdentifier: "Pacific/Apia")
        #expect(throws: BirthProfileError.nonexistentLocalDate) { try engine.natalCharts(for: skipped) }
    }

    @Test func localZoneControlsCivilDayButNotSolarTermInstant() throws {
        let instant = date("2026-02-06T12:30:00+08:00")
        let beijing = try engine.chart(at: instant)
        let losAngeles = try engine.chart(at: instant, timeZone: #require(TimeZone(identifier: "America/Los_Angeles")))
        #expect(beijing.year == losAngeles.year)
        #expect(beijing.month == losAngeles.month)
        #expect(beijing.previousJie == losAngeles.previousJie)
        #expect(beijing.day != losAngeles.day)
    }

    @Test func nativeSolarTermsAgreeWithOfficialHKOMinuteReferences() throws {
        // Official HKO sources; times are UTC+8 and rounded to minutes:
        // https://www.hko.gov.hk/en/gts/astron2025/files/2025cal02.pdf
        // https://www.hko.gov.hk/en/gts/astron2026/files/2026cal02.pdf
        // https://www.hko.gov.hk/en/gts/astron2026/files/2026cal09.pdf
        // https://www.hko.gov.hk/en/gts/astron2026/files/2026SolarTerms24.pdf
        let references: [(Int, Int, String)] = [
            (2025, 2, "2025-02-03T22:10:00+08:00"),
            (2026, 2, "2026-02-04T04:02:00+08:00"),
            (2026, 11, "2026-06-21T16:25:00+08:00"),
            (2026, 16, "2026-09-07T22:41:00+08:00"),
            (2026, 17, "2026-09-23T08:05:00+08:00"),
            (2026, 23, "2026-12-22T04:50:00+08:00")
        ]
        let native = FourPillarsEngine()
        for (year, index, expected) in references {
            let actual = try #require(native.solarTerms(in: year).first { $0.index == index })
            let deviation = abs(actual.date.timeIntervalSince(date(expected)))
            #expect(deviation < 90, "\(year) \(actual.name) differs from HKO by \(deviation) seconds")
        }
    }

    @Test func nativeLichunAndMonthlyJieUseInstantBoundaries() throws {
        let native = FourPillarsEngine()
        let terms = try native.solarTerms(in: 2026)
        let lichun = try #require(terms.first { $0.name == "立春" })
        let before = try native.chart(at: lichun.date.addingTimeInterval(-1))
        let after = try native.chart(at: lichun.date)
        #expect([before.year.text, before.month.text] == ["乙巳", "己丑"])
        #expect([after.year.text, after.month.text] == ["丙午", "庚寅"])
        let baiLu = try #require(terms.first { $0.name == "白露" })
        #expect(try native.chart(at: baiLu.date.addingTimeInterval(-1)).month.text == "丙申")
        #expect(try native.chart(at: baiLu.date).month.text == "丁酉")
        let qiuFen = try #require(terms.first { $0.name == "秋分" })
        #expect(try native.chart(at: qiuFen.date.addingTimeInterval(-1)).month == native.chart(at: qiuFen.date).month)
    }

    @Test func nativeDayAnchorAndMidnightLateZiAreConsistent() throws {
        // HKO March 2010 calendar: March 15 is 甲子.
        // https://www.hko.gov.hk/tc/gts/astron2010/files/03_2010c.pdf
        let native = FourPillarsEngine()
        let beforeZi = try native.chart(at: date("2010-03-15T22:59:59+08:00"))
        let lateZi = try native.chart(at: date("2010-03-15T23:00:00+08:00"))
        let ziDay = try native.chart(at: date("2010-03-15T23:00:00+08:00"), dayBoundary: .ziHour23)
        let afterMidnight = try native.chart(at: date("2010-03-16T00:00:00+08:00"))
        #expect(beforeZi.day.text == "甲子")
        #expect(lateZi.day.text == "甲子")
        #expect(ziDay.day.text == "乙丑")
        #expect(afterMidnight.day.text == "乙丑")
        #expect(lateZi.hour?.text == "丙子")
        #expect(lateZi.hour == afterMidnight.hour)
    }

    @Test func nativeKnownChartsMatchPinnedUpstreamFixtures() throws {
        // https://github.com/6tail/lunar-swift/blob/1.1.8/Tests/LunarSwiftTests/EightCharTests.swift
        let native = FourPillarsEngine()
        let first = try native.chart(at: date("2005-12-23T08:37:00+08:00"))
        #expect([first.year.text, first.month.text, first.day.text, first.hour?.text] == ["乙酉", "戊子", "辛巳", "壬辰"])
        let second = try native.chart(at: date("1982-01-29T06:00:00+08:00"))
        #expect([second.year.text, second.month.text, second.day.text, second.hour?.text] == ["辛酉", "辛丑", "壬子", "癸卯"])
        let late = try native.chart(at: date("1988-02-15T23:30:00+08:00"))
        #expect([late.year.text, late.month.text, late.day.text, late.hour?.text] == ["戊辰", "甲寅", "庚子", "戊子"])
    }

    @Test func nativeUnknownBirthOnActualLichunRetainsCandidatesAcrossZones() throws {
        let native = FourPillarsEngine()
        let unknown = BirthProfile(birthYear: 2026, birthMonth: 2, birthDay: 4)
        let charts = try native.natalCharts(for: unknown)
        #expect(charts.count == 2)
        #expect(charts.map(\.year.text) == ["乙巳", "丙午"])
        #expect(charts.allSatisfy { $0.hour == nil })
        var zi = unknown
        zi.dayBoundary = .ziHour23
        #expect(try native.natalCharts(for: zi).count == 3)
        let overseas = BirthProfile(birthYear: 2026, birthMonth: 2, birthDay: 3, timeZoneIdentifier: "America/Los_Angeles")
        let overseasCharts = try native.natalCharts(for: overseas)
        #expect(overseasCharts.count == 2)
        #expect(overseasCharts.map(\.year) == charts.map(\.year))
        #expect(overseasCharts[0].day != charts[0].day)
    }

    @Test func nativeProviderCoversDocumentedEdgesAndRejectsUnsupportedDates() throws {
        let native = FourPillarsEngine()
        for year in [1901, 1950, 2000, 2050, 2099] {
            let terms = try native.solarTerms(in: year)
            #expect(terms.count == 24)
            #expect(terms.map(\.index) == Array(0..<24))
            #expect(zip(terms, terms.dropFirst()).allSatisfy { $0.date < $1.date })
            #expect(terms.filter(\.isJie).count == 12)
            #expect(try native.solarTerms(in: year) == terms)
        }
        #expect(try native.chart(at: date("1901-01-01T00:00:00+08:00")).hour != nil)
        #expect(try native.chart(at: date("2099-12-31T23:59:00+08:00"), dayBoundary: .ziHour23).hour != nil)
        #expect(throws: FourPillarsError.unsupportedYear) { try native.chart(at: date("1900-12-31T23:00:00+08:00")) }
        #expect(throws: FourPillarsError.unsupportedYear) { try native.solarTerms(in: 2100) }
        #expect(throws: FourPillarsError.invalidInstant) { try native.chart(at: Date(timeIntervalSince1970: .infinity)) }
    }
}
