import Foundation
import Testing
@testable import LingxiCore

struct LuckCycleTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private static func syntheticTerms(year: Int) -> [SolarTermBoundary] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return (0..<24).map { index in
            let date = calendar.date(from: DateComponents(year: year, month: index / 2 + 1,
                                                          day: index.isMultiple(of: 2) ? 6 : 21, hour: 12))!
            return SolarTermBoundary(index: index, date: date)
        }
    }

    @Test func minuteMethodMatchesEightPythonSectTwoReferenceRecords() throws {
        for item in try NatalLuckFixture.load().cases {
            let report = try LuckCycleEngine().calculate(for: item.profile, gender: item.gender, cycleCount: 3)
            #expect(report.direction.rawValue == item.direction)
            let offset = report.startOffset
            #expect([offset.years, offset.months, offset.days, offset.hours] == item.offset, "Offset: \(item.id)")
            #expect(abs(report.startAt.timeIntervalSince(date(item.startAt))) < 0.001, "Handover: \(item.id)")
            #expect(report.cycles.map(\.pillar.text) == item.firstThreePillars)
        }
    }

    @Test func unknownBirthTimeAndInvalidCountsAreRejected() throws {
        let profile = BirthProfile(birthYear: 1990, birthMonth: 1, birthDay: 1)
        #expect(throws: LuckCycleError.birthTimeRequired) { try LuckCycleEngine().calculate(for: profile, gender: .male) }
        #expect(throws: LuckCycleError.invalidCycleCount) { try LuckCycleEngine().calculate(for: profile, gender: .female, cycleCount: 0) }
        #expect(throws: LuckCycleError.invalidCycleCount) { try LuckCycleEngine().calculate(for: profile, gender: .female, cycleCount: 13) }
    }

    @Test func exactHandoverBoundariesHaveNoMissingDayOrDoubleMembership() throws {
        let item = try #require(NatalLuckFixture.load().cases.first)
        let report = try LuckCycleEngine().calculate(for: item.profile, gender: item.gender, cycleCount: 3)
        #expect(report.activeCycle(at: report.startAt.addingTimeInterval(-0.001)) == nil)
        #expect(report.activeCycle(at: report.startAt)?.index == 1)
        for (current, next) in zip(report.cycles, report.cycles.dropFirst()) {
            #expect(current.end == next.start)
            #expect(report.activeCycle(at: current.end.addingTimeInterval(-0.001))?.index == current.index)
            #expect(report.activeCycle(at: current.end)?.index == next.index)
            #expect(!current.contains(next.start))
        }
    }

    @Test func sameAbsoluteBirthAndJiePreserveYearMonthDirectionAndOffsetAcrossZones() throws {
        let beijing = BirthProfile(birthYear: 2026, birthMonth: 2, birthDay: 4, birthHour: 4,
                                   birthMinute: 1, birthTimeKnown: true, timeZoneIdentifier: "Asia/Shanghai")
        let newYork = BirthProfile(birthYear: 2026, birthMonth: 2, birthDay: 3, birthHour: 15,
                                   birthMinute: 1, birthTimeKnown: true, timeZoneIdentifier: "America/New_York")
        let engine = LuckCycleEngine()
        for gender in LuckGender.allCases {
            let a = try engine.calculate(for: beijing, gender: gender)
            let b = try engine.calculate(for: newYork, gender: gender)
            #expect(a.birthInstant == b.birthInstant)
            #expect(a.birthChart.year == b.birthChart.year)
            #expect(a.birthChart.month == b.birthChart.month)
            #expect(a.direction == b.direction)
            #expect(a.startOffset == b.startOffset)
            #expect(a.boundaryJie == b.boundaryJie)
        }
    }

    @Test func dstDoesNotCreateAnExtraHourInTheAstronomicalInterval() throws {
        let provider = FourPillarsEngine(solarTermsProvider: { Self.syntheticTerms(year: $0) })
        let profile = BirthProfile(birthYear: 2026, birthMonth: 3, birthDay: 7, birthHour: 12,
                                   birthMinute: 0, birthTimeKnown: true, timeZoneIdentifier: "America/New_York")
        let report = try LuckCycleEngine(fourPillars: provider).calculate(for: profile, gender: .male)
        #expect(report.boundaryJie.date == date("2026-04-06T12:00:00Z"))
        #expect(report.birthInstant == date("2026-03-07T17:00:00Z"))
        #expect(report.startOffset.elapsedMinutes == 29 * 1440 + 19 * 60)
        // Wall clocks go from March 7 noon EST to April 6 08:00 EDT: that naive
        // civil subtraction would incorrectly count one more hour.
        #expect(report.startOffset.elapsedMinutes != 29 * 1440 + 20 * 60)
    }

    @Test func leapDayHandoverUsesOriginalAnchorAcrossDecades() throws {
        let provider = FourPillarsEngine(solarTermsProvider: { year in
            Self.syntheticTerms(year: year).map { term in
                if year == 2016 && term.index == 2 {
                    return SolarTermBoundary(index: 2, date: ISO8601DateFormatter().date(from: "2016-02-29T12:00:00Z")!)
                }
                return term
            }
        })
        let profile = BirthProfile(birthYear: 2016, birthMonth: 2, birthDay: 29, birthHour: 12,
                                   birthMinute: 0, birthTimeKnown: true, timeZoneIdentifier: "UTC")
        let result = try LuckCycleEngine(fourPillars: provider).calculate(for: profile, gender: .female, cycleCount: 3)
        #expect(result.direction == .backward)
        #expect(result.startOffset.elapsedMinutes == 0)
        #expect(result.cycles[1].start == date("2026-02-28T12:00:00Z"))
        #expect(result.cycles[2].start == date("2036-02-29T12:00:00Z"))
    }

    @Test func flowYearsChangeAtLichunAndIntersectActualCycleIntervals() throws {
        let engine = LuckCycleEngine()
        let flow = try engine.flowYear(2026)
        let fourPillars = FourPillarsEngine()
        #expect(try fourPillars.chart(at: flow.start.addingTimeInterval(-0.001)).year.text == "乙巳")
        #expect(try fourPillars.chart(at: flow.start).year == flow.pillar)
        #expect(try engine.flowYear(2027).start == flow.end)
        #expect(!flow.contains(date("2026-01-01T12:00:00+08:00")))
        let item = try #require(NatalLuckFixture.load().cases.first)
        let cycle = try #require(engine.calculate(for: item.profile, gender: item.gender).cycles.first)
        let years = try engine.flowYears(in: cycle)
        #expect(years.count == 11)
        #expect(years.allSatisfy { $0.start < cycle.end && cycle.start < $0.end })
        #expect(try #require(years.first).start <= cycle.start)
        #expect(try #require(years.last).end >= cycle.end)
        for (a, b) in zip(years, years.dropFirst()) { #expect(a.end == b.start) }
    }

    @Test func finalSupportedFlowYearKeepsTheInjectedPaddingProvider() throws {
        let provider = FourPillarsEngine(solarTermsProvider: { Self.syntheticTerms(year: $0) })
        let engine = LuckCycleEngine(fourPillars: provider)
        let flow = try engine.flowYear(2099)
        #expect(flow.end == date("2100-02-06T12:00:00Z"))
        #expect(throws: LuckCycleError.unsupportedFlowYear) { try engine.flowYear(2100) }
    }

    @Test func referenceSecondRoundingCarriesBeforeMinuteConversion() throws {
        let provider = FourPillarsEngine(solarTermsProvider: { year in
            Self.syntheticTerms(year: year).map { term in
                // March's Jie moves to 12:00:59.8 and is represented as 12:01:00
                // by lunar's Solar object before its sect 2 minute subtraction.
                SolarTermBoundary(index: term.index, date: term.index == 4 ? term.date.addingTimeInterval(59.8) : term.date)
            }
        })
        let profile = BirthProfile(birthYear: 2026, birthMonth: 3, birthDay: 6, birthHour: 12,
                                   birthMinute: 0, birthTimeKnown: true, timeZoneIdentifier: "UTC")
        let result = try LuckCycleEngine(fourPillars: provider).calculate(for: profile, gender: .male)
        #expect(result.startOffset.elapsedMinutes == 1)
        #expect(result.startOffset.hours == 2)
        #expect(result.startAt == date("2026-03-06T14:00:00Z"))
    }

    @Test func flowMonthsCoverLichunThroughXiaohanWithExactHalfOpenBoundaries() throws {
        let engine = LuckCycleEngine()
        let year = try engine.flowYear(2026)
        let months = try engine.flowMonths(in: year)
        #expect(months.count == 12)
        #expect(months.map(\.index) == Array(1...12))
        #expect(months.map(\.pillar.text) == ["庚寅", "辛卯", "壬辰", "癸巳", "甲午", "乙未", "丙申", "丁酉", "戊戌", "己亥", "庚子", "辛丑"])
        #expect(months[0].start == year.start)
        #expect(months[0].label == "寅月")
        #expect(months[0].startJieName == "立春")
        #expect(months[11].startJieName == "小寒")
        #expect(months[11].endJieName == "立春")
        #expect(months[11].end == year.end)
        let fourPillars = FourPillarsEngine()
        for month in months {
            #expect(try fourPillars.chart(at: month.start).month == month.pillar)
            #expect(try fourPillars.chart(at: month.start.addingTimeInterval(-0.001)).month != month.pillar)
            #expect(month.contains(month.start))
            #expect(!month.contains(month.end))
        }
        for (a, b) in zip(months, months.dropFirst()) {
            #expect(a.end == b.start)
            #expect(a.contains(b.start.addingTimeInterval(-0.001)))
            #expect(!a.contains(b.start))
        }
        #expect(!months.contains { $0.contains(year.end) })
        #expect(try engine.flowMonths(in: engine.flowYear(2027))[0].contains(year.end))
    }

    @Test func finalYearFlowMonthsUsePaddingForBothXiaohanAndFinalLichun() throws {
        let provider = FourPillarsEngine(solarTermsProvider: { Self.syntheticTerms(year: $0) })
        let engine = LuckCycleEngine(fourPillars: provider)
        let year = try engine.flowYear(2099)
        let months = try engine.flowMonths(in: year)
        #expect(months.count == 12)
        #expect(months[0].start == date("2099-02-06T12:00:00Z"))
        #expect(months[11].start == date("2100-01-06T12:00:00Z"))
        #expect(months[11].end == date("2100-02-06T12:00:00Z"))
        #expect(months[11].startJieName == "小寒")
        #expect(months[11].end == year.end)
    }

    @Test func cycleAfterLastSupportedLichunThrowsInsteadOfReturningEmptyYears() throws {
        let cycle = LuckCycle(index: 10, pillar: Ganzhi(index: 0), start: date("2100-06-01T12:00:00Z"),
                              end: date("2110-06-01T12:00:00Z"), nominalStartAge: 95)
        #expect(throws: LuckCycleError.unsupportedFlowYear) { try LuckCycleEngine().flowYears(in: cycle) }
    }
}
