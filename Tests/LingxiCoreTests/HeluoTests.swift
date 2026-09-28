import Foundation
import Testing
@testable import LingxiCore

struct HeluoTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func profile() -> BirthProfile {
        BirthProfile(name: "Synthetic fixture", birthYear: 1990, birthMonth: 6, birthDay: 15,
                     birthHour: 9, birthMinute: 30, birthTimeKnown: true,
                     timeZoneIdentifier: "Etc/GMT-8", luckGender: .male)
    }
    private func syntheticEngine() -> HeluoEngine {
        HeluoEngine(fourPillars: FourPillarsEngine(solarTermsProvider: { year in
            let utc = TimeZone(secondsFromGMT: 0)!
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
            return (0..<24).map { index in
                SolarTermBoundary(index: index, date: calendar.date(from: DateComponents(
                    year: year, month: index / 2 + 1, day: index.isMultiple(of: 2) ? 6 : 21, hour: 12
                ))!)
            }
        }))
    }

    @Test func numericResultsMatch173SyntheticPrivateReferenceCalculations() throws {
        let fixture = try HeluoFixture.load()
        #expect(fixture.cases.count == 173)
        let engine = HeluoEngine()
        for (index, item) in fixture.cases.enumerated() {
            let pieces = item.birth.split(whereSeparator: { "-T:".contains($0) }).map { Int($0)! }
            let profile = BirthProfile(birthYear: pieces[0], birthMonth: pieces[1], birthDay: pieces[2],
                birthHour: pieces[3], birthMinute: pieces[4], birthTimeKnown: true,
                timeZoneIdentifier: "Etc/GMT-8", dayBoundary: item.dayBoundary, luckGender: item.gender)
            let native = try engine.calculate(for: profile, at: date(item.query.replacingOccurrences(of: "+08:00", with: ":00+08:00")))
            let nativePillars = try FourPillarsEngine().natalCharts(for: profile)[0]
            #expect([nativePillars.year.text, nativePillars.month.text, nativePillars.day.text, nativePillars.hour!.text] == item.natalPillars)
            #expect(native.tianNumber == item.tianNumber, "case \(index)")
            #expect(native.diNumber == item.diNumber, "case \(index)")
            #expect(native.xianTian.hexagram.number == item.xianTian, "case \(index)")
            #expect(native.houTian.hexagram.number == item.houTian, "case \(index)")
            #expect(native.xianTian.linePosition == item.yuanTang, "case \(index)")
            #expect(native.houTian.linePosition == item.yuanTang)
            #expect(native.year?.marked.hexagram.number == item.year, "case \(index)")
            #expect(native.year?.marked.linePosition == item.yearLine)
            #expect(native.month?.marked.hexagram.number == item.month, "case \(index)")
            #expect(native.month?.marked.linePosition == item.monthLine)
            #expect(native.month?.monthIndex == item.monthIndex)
            #expect(native.day?.marked.hexagram.number == item.day, "case \(index)")
            #expect(native.day?.marked.linePosition == item.dayLine)
            #expect(native.day?.dayIndex == item.dayIndex)
            #expect(native.day?.triggerLinePosition == item.triggerLine)
            #expect(native.nominalAge == item.nominalAge)
            #expect(native.lifeSegments[5].endAge == item.firstPhaseEndAge)
            #expect(native.lifeSegments.last?.endAge == item.lastAge)
            #expect(native.currentLifeSegment?.phase == item.phase)
            #expect(native.flowUnavailableReason == nil)
        }
    }

    @Test func all64PublicDomainHexagramMappingsPreserveBottomToTopLines() throws {
        let fixture = try HeluoFixture.load()
        #expect(fixture.hexagrams.count == 64)
        for item in fixture.hexagrams {
            let actual = HeluoEngine.hexagram(lines: item.lines.map { $0 == 1 })
            #expect(actual.number == item.number)
            #expect(actual.name == item.name)
            #expect(!actual.theme.isEmpty)
            #expect(!actual.reflection.isEmpty)
        }
    }

    @Test func missingInputsAndUnsupportedInstantsReturnExplicitErrors() throws {
        var unknown = profile(); unknown.birthTimeKnown = false
        #expect(throws: HeluoError.birthTimeRequired) { try HeluoEngine().calculate(for: unknown, at: date("2026-09-17T04:00:00Z")) }
        unknown = profile(); unknown.luckGender = nil
        #expect(throws: HeluoError.genderRequired) { try HeluoEngine().calculate(for: unknown, at: date("2026-09-17T04:00:00Z")) }
        #expect(throws: HeluoError.invalidInstant) { try HeluoEngine().calculate(for: profile(), at: Date(timeIntervalSince1970: .nan)) }
        #expect(throws: HeluoError.unsupportedDate) { try HeluoEngine().calculate(for: profile(), at: date("2100-03-01T04:00:00Z")) }
    }

    @Test func liChunChangesYearAgeMonthAndDayAtExactInstant() throws {
        let engine = syntheticEngine(), crossing = date("2026-02-06T12:00:00Z")
        let before = try engine.calculate(for: profile(), at: crossing.addingTimeInterval(-0.001))
        let at = try engine.calculate(for: profile(), at: crossing)
        #expect(before.year?.flowYear == 2025)
        #expect(at.year?.flowYear == 2026)
        #expect(at.nominalAge == before.nominalAge + 1)
        #expect(before.month?.monthIndex == 12)
        #expect(at.month?.monthIndex == 1)
        #expect(before.year?.end == at.year?.start)
        #expect(before.month?.end == at.month?.start)
        #expect(before.day?.end == crossing)
        #expect(at.day?.start == crossing)
        #expect(at.day?.dayIndex == 0)
        #expect(at.day?.marked.linePosition == 1)
    }

    @Test func decemberJanuaryIntervalsAreForwardAndContinuous() throws {
        let engine = syntheticEngine()
        let december = try engine.calculate(for: profile(), at: date("2026-12-20T04:00:00Z"))
        let january = try engine.calculate(for: profile(), at: date("2027-01-07T04:00:00Z"))
        #expect(december.year?.flowYear == 2026)
        #expect(january.year?.flowYear == 2026)
        #expect(december.month?.monthIndex == 11)
        #expect(january.month?.monthIndex == 12)
        #expect(december.month?.end == january.month?.start)
        #expect(january.month!.start < january.month!.end)
        let newYear = try engine.calculate(for: profile(), at: date("2027-01-01T04:00:00Z"))
        #expect(newYear.year?.marked == december.year?.marked)
        #expect(newYear.nominalAge == december.nominalAge)
    }

    @Test func sixDayBlocksChangeHexagramOnlyAtSeventhCivilDay() throws {
        let engine = syntheticEngine()
        let first = try engine.calculate(for: profile(), at: date("2026-09-06T13:00:00Z"))
        let sixth = try engine.calculate(for: profile(), at: date("2026-09-11T13:00:00Z"))
        let seventh = try engine.calculate(for: profile(), at: date("2026-09-12T13:00:00Z"))
        #expect(first.day?.marked.hexagram == sixth.day?.marked.hexagram)
        #expect(first.day?.marked.linePosition == 1)
        #expect(sixth.day?.marked.linePosition == 6)
        #expect(seventh.day?.marked.linePosition == 1)
        #expect(seventh.day?.marked.hexagram != sixth.day?.marked.hexagram)
        #expect(first.day?.blockIndex == 1)
        #expect(seventh.day?.blockIndex == 2)
    }

    @Test func dailyLineBoundaryIsMidnightEvenWhenBirthPolicyIs23() throws {
        var value = profile(); value.dayBoundary = .ziHour23
        let engine = syntheticEngine()
        let at22 = try engine.calculate(for: value, at: date("2026-09-17T14:59:00Z"))
        let at23 = try engine.calculate(for: value, at: date("2026-09-17T15:00:00Z"))
        let midnight = try engine.calculate(for: value, at: date("2026-09-17T16:00:00Z"))
        #expect(at22.day == at23.day)
        #expect(at23.day?.end == midnight.day?.start)
        #expect(midnight.day?.dayIndex == at23.day!.dayIndex! + 1)
    }

    @Test func historicalDSTUsesLocalCivilDaysInsteadOfElapsed24Hours() throws {
        var value = profile(); value.timeZoneIdentifier = "America/New_York"
        let engine = syntheticEngine()
        let spring = try engine.calculate(for: value, at: date("2026-03-08T12:00:00Z"))
        #expect(spring.day!.end.timeIntervalSince(spring.day!.start) == 23 * 3600)
        let fall = try engine.calculate(for: value, at: date("2026-11-01T12:00:00Z"))
        #expect(fall.day!.end.timeIntervalSince(fall.day!.start) == 25 * 3600)
        #expect(spring.methodNotes.contains { $0.contains("历史夏令时") })
    }

    @Test func beforeBirthAndBeyondLifeSegmentsKeepNatalButNeverInventFlows() throws {
        let engine = HeluoEngine()
        let unborn = try engine.calculate(for: profile(), at: date("1989-06-15T04:00:00Z"))
        #expect(unborn.year == nil && unborn.month == nil && unborn.day == nil)
        #expect(unborn.currentLifeSegment == nil)
        #expect(unborn.flowUnavailableReason?.contains("早于") == true)
        var value = profile(); value.birthYear = 1901
        let beyond = try engine.calculate(for: value, at: date("2099-12-31T04:00:00Z"))
        #expect(beyond.year == nil && beyond.month == nil && beyond.day == nil)
        #expect(beyond.flowUnavailableReason?.contains("不是寿命判断") == true)
        #expect((1...64).contains(beyond.xianTian.hexagram.number))
    }

    @Test func lifePhaseAndFinalHorizonSwitchOnlyAtLiChun() throws {
        let engine = syntheticEngine()
        let initial = try engine.calculate(for: profile(), at: date("2026-09-17T04:00:00Z"))
        let transitionYear = initial.lifeSegments[6].startYear
        let transition = date("\(transitionYear)-02-06T12:00:00Z")
        let before = try engine.calculate(for: profile(), at: transition.addingTimeInterval(-0.001))
        let after = try engine.calculate(for: profile(), at: transition)
        #expect(before.currentLifeSegment?.phase == "先天")
        #expect(after.currentLifeSegment?.phase == "后天")
        #expect(after.currentLifeSegment?.startAge == before.currentLifeSegment!.endAge + 1)
        let lastYear = initial.lifeSegments.last!.endYear + 1
        let horizon = date("\(lastYear)-02-06T12:00:00Z")
        let final = try engine.calculate(for: profile(), at: horizon.addingTimeInterval(-0.001))
        let beyond = try engine.calculate(for: profile(), at: horizon)
        #expect(final.year != nil && final.day != nil)
        #expect(beyond.year == nil && beyond.day == nil)
        #expect(beyond.flowUnavailableReason != nil)
    }

    @Test func edgeYearsAndReportCodableRemainUsable() throws {
        var value = profile(); value.birthYear = 1901; value.birthMonth = 1; value.birthDay = 1
        let earliest = try HeluoEngine().calculate(for: value, at: date("1901-01-02T04:00:00Z"))
        #expect(earliest.year?.flowYear == 1900)
        value.birthYear = 2099
        let latest = try HeluoEngine().calculate(for: value, at: date("2099-12-31T04:00:00Z"))
        #expect(latest.month?.monthIndex == 11)
        let bytes = try JSONEncoder().encode(latest)
        #expect(try JSONDecoder().decode(HeluoReport.self, from: bytes) == latest)
    }
}

private struct HeluoFixture: Decodable {
    let hexagrams: [Hexagram]
    let cases: [Case]
    struct Hexagram: Decodable { let number: Int; let name: String; let lines: [Int] }
    struct Case: Decodable {
        let birth: String; let gender: LuckGender; let query: String; let dayBoundary: BirthDayBoundary
        let natalPillars: [String]
        let tianNumber: Int; let diNumber: Int; let xianTian: Int; let houTian: Int; let yuanTang: Int
        let year: Int; let yearLine: Int; let month: Int; let monthLine: Int; let monthIndex: Int
        let day: Int; let dayLine: Int; let dayIndex: Int; let triggerLine: Int
        let nominalAge: Int; let firstPhaseEndAge: Int; let lastAge: Int; let phase: String
    }
    static func load() throws -> Self {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/heluo-reference.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
