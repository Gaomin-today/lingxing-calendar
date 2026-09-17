import Foundation
import Testing
@testable import LingxiCore

struct AutomationFactsTests {
    private let engine = FourPillarsEngine()
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    @Test func chartExportsRecordedZonePolicyAndDetailedKnownPillarsWithoutInventingHour() throws {
        let profile = BirthProfile(name: "时刻未知", birthYear: 1990, birthMonth: 1, birthDay: 15,
                                   timeZoneIdentifier: "America/New_York", dayBoundary: .ziHour23)
        let native = try engine.natalCharts(for: profile)[0]
        let value = AutomationFacts.chart(native)
        #expect(value["timeZoneIdentifier"]?.stringValue == "America/New_York")
        #expect(value["dayBoundary"]?.stringValue == "ziHour23")
        #expect(value["hasUnknownBirthHour"]?.boolValue == true)
        #expect(value["instantRole"]?.stringValue == "candidateReference")
        #expect(value["knownPillarCount"]?.intValue == 3)
        #expect(value["pillars"]?["hour"] == .null)
        #expect(value["pillars"]?["day"]?["pillar"]?["text"]?.stringValue == native.day.text)
        let month = value["pillars"]?["month"]
        #expect(month?["hiddenStems"]?.arrayValue?.isEmpty == false)
        #expect(month?["naYin"]?.stringValue?.isEmpty == false)
        #expect(month?["dayMasterStage"]?.stringValue?.isEmpty == false)
        #expect(month?["selfStage"]?.stringValue?.isEmpty == false)
        #expect(month?["xunKong"]?.stringValue?.isEmpty == false)
        #expect(value["sources"]?.arrayValue?.count == 2)
        #expect(try AutomationJSON.decode(JSONValue.self, from: AutomationJSON.encode(value)) == value)
    }

    @Test func exactJieBoundariesPreserveAbsoluteCalculationTimeAndChangePillarsAtBoundary() throws {
        let lichun = try engine.solarTerms(in: 2026).first { $0.name == "立春" }!
        let before = try engine.chart(at: lichun.date.addingTimeInterval(-0.001), timeZone: TimeZone(identifier: "Europe/London")!)
        let after = try engine.chart(at: lichun.date, timeZone: TimeZone(identifier: "Europe/London")!)
        let left = AutomationFacts.chart(before)
        let right = AutomationFacts.chart(after)
        #expect(left["pillars"]?["year"]?["pillar"]?["text"]?.stringValue == "乙巳")
        #expect(right["pillars"]?["year"]?["pillar"]?["text"]?.stringValue == "丙午")
        #expect(right["previousJie"]?["unixSeconds"] == .number(lichun.date.timeIntervalSince1970))
        #expect(right["instantUnixSeconds"] == .number(lichun.date.timeIntervalSince1970))
        #expect(right["previousJie"]?["date"]?.stringValue?.hasSuffix("Z") == true)
        #expect(right["pillars"]?["hour"] != .null)
        #expect(right["instantRole"]?.stringValue == "resolvedInstant")
    }

    @Test func luckAndFlowYearDTOsKeepRealHandoverAndJieMonthIntervals() throws {
        let profile = BirthProfile(name: "合成资料", birthYear: 1990, birthMonth: 8, birthDay: 12,
                                   birthHour: 9, birthMinute: 30, birthTimeKnown: true,
                                   timeZoneIdentifier: "Asia/Shanghai")
        let luckEngine = LuckCycleEngine()
        let native = try luckEngine.calculate(for: profile, gender: .female)
        let exported = AutomationFacts.luck(native)
        #expect(exported["direction"]?.stringValue == native.direction.rawValue)
        #expect(exported["startOffset"]?["elapsedMinutes"]?.intValue == native.startOffset.elapsedMinutes)
        #expect(exported["cycles"]?.arrayValue?.count == 10)
        #expect(exported["startAt"] == exported["cycles"]?.arrayValue?.first?["start"])
        #expect(exported["cycles"]?.arrayValue?[0]["end"] == exported["cycles"]?.arrayValue?[1]["start"])
        let year = try luckEngine.flowYear(2026)
        let months = try luckEngine.flowMonths(in: year)
        let flow = AutomationFacts.flowYear(year, months: months)
        #expect(flow["months"]?.arrayValue?.count == 12)
        #expect(flow["start"] == flow["months"]?.arrayValue?.first?["start"])
        #expect(flow["end"] == flow["months"]?.arrayValue?.last?["end"])
        #expect(flow["months"]?.arrayValue?.first?["startJieName"]?.stringValue == "立春")
    }

    @Test func almanacDTOIncludesAllThirteenCivilTimeSlotsAndTraditionalSources() throws {
        let native = try AlmanacEngine.shared.day(on: date("2026-09-17T04:00:00Z"))
        let exported = AutomationFacts.almanac(native)
        #expect(exported["calendarDate"]?.stringValue == "2026-09-17")
        #expect(exported["timeZoneIdentifier"]?.stringValue == "Asia/Shanghai")
        #expect(exported["hours"]?.arrayValue?.count == 13)
        #expect(exported["hours"]?.arrayValue?.first?["label"]?.stringValue == "早子时")
        #expect(exported["hours"]?.arrayValue?.last?["endMinute"]?.intValue == 1440)
        #expect(exported["dayNineStar"]?["palaces"]?.arrayValue?.count == 9)
        #expect(exported["hours"]?.arrayValue?.last?["nineStar"]?["palaces"]?.arrayValue?.count == 9)
        #expect(exported["sourceURL"]?.stringValue == AlmanacEngine.sourceURL)
        #expect(exported["boundaryNote"]?.stringValue == AlmanacEngine.boundaryNote)
        #expect(exported["classification"]?.stringValue == "traditionalRules")
    }

    @Test func readingDTOSeparatesUnspecifiedStrengthFromEvidenceAndConditionalInterpretation() throws {
        let natal = try engine.chart(at: date("1990-08-12T01:30:00Z"), includeHour: false)
        let flow = try engine.chart(at: date("2026-09-17T04:00:00Z"))
        let native = try PersonalDailyReadingEngine().analyze(natal: natal, flow: flow)
        let exported = AutomationFacts.reading(native)
        #expect(exported["strength"]?.stringValue == "unspecified")
        #expect(exported["hasUnknownBirthHour"]?.boolValue == true)
        #expect(exported["periods"]?.arrayValue?.count == 3)
        #expect(exported["natalMonth"]?["pillar"]?["text"]?.stringValue == natal.month.text)
        #expect(exported["flowMonth"]?["pillar"]?["text"]?.stringValue == flow.month.text)
        #expect(exported["observations"]?.arrayValue?.count == native.observations.count)
        #expect(exported["rootEvidence"]?.arrayValue?.count == native.rootEvidence.count)
        #expect(exported["relationships"]?["checkedPillarCount"]?.intValue == 3)
        #expect(exported["actions"]?.arrayValue?.count == native.actions.count)
        #expect(exported["scopeNote"]?.stringValue == native.scopeNote)
    }
}
