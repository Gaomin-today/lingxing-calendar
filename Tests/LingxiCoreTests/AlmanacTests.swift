import Foundation
import Testing
@testable import LingxiCore

struct AlmanacTests {
    private let calendar = CalendarEngine().gregorian

    private func date(_ text: String, hour: Int = 12, minute: Int = 0) -> Date {
        let p = text.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour, minute: minute))!
    }

    @Test func testDayAndAll13HoursAgainstActualWannianliEngine() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/almanac-reference.json")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let reference = try decoder.decode(Reference.self, from: Data(contentsOf: url))
        #expect(reference.source == "wannianli.engine.build_calendar_day")
        #expect(reference.dependency == "lunar_python==1.4.8")
        #expect(reference.cases.count == 6)
        for sample in reference.cases {
            let value = try AlmanacEngine.shared.day(on: date(sample.date))
            #expect(value.yi == sample.day.yi)
            #expect(value.ji == sample.day.ji)
            #expect(value.auspiciousGods == sample.day.jiShen)
            #expect(value.inauspiciousGods == sample.day.xiongSha)
            #expect(value.dutyGod == sample.day.tianShen)
            #expect(value.dutyGodType == sample.day.tianShenType)
            #expect(value.luck == sample.day.luck)
            #expect(value.clash == sample.day.chongDesc)
            #expect(value.sha == sample.day.sha)
            #expect(value.yearNineStar.number == sample.stars["year"])
            #expect(value.monthNineStar.number == sample.stars["month"])
            #expect(value.dayNineStar.number == sample.stars["day"])
            checkPositions(value.positions, sample.positions)
            for sampleHour in sample.hours {
                let hour = try AlmanacEngine.shared.hour(at: date(sample.date, hour: sampleHour.hour))
                #expect(hour.ganZhi == sampleHour.ganZhi)
                #expect(hour.yi == sampleHour.yi)
                #expect(hour.ji == sampleHour.ji)
                #expect(hour.dutyGod == sampleHour.tianShen)
                #expect(hour.dutyGodType == sampleHour.tianShenType)
                #expect(hour.luck == sampleHour.tianShenLuck)
                #expect(hour.clash == sampleHour.chongDesc)
                #expect(hour.sha == sampleHour.sha)
                #expect(hour.nineStar.number == sampleHour.star)
                checkPositions(hour.positions, sampleHour.positions)
            }
        }
    }

    private func checkPositions(_ positions: [AlmanacPosition], _ reference: [String: Position]) {
        for (label, key) in [("喜神", "xi"), ("财神", "cai"), ("福神", "fu"), ("阳贵", "yangGui"), ("阴贵", "yinGui")] {
            // Dictionary keys are not affected by JSONDecoder's key strategy.
            let refKey = key == "yangGui" ? "yang_gui" : key == "yinGui" ? "yin_gui" : key
            #expect(positions.first { $0.label == label }?.raw == reference[refKey]?.raw)
            #expect(positions.first { $0.label == label }?.direction == reference[refKey]?.desc)
        }
    }

    @Test func testCivilDayAndLateZiBoundariesAreIndependent() throws {
        let engine = AlmanacEngine.shared
        let start = try engine.day(on: date("1988-02-15", hour: 0))
        let late = try engine.day(on: date("1988-02-15", hour: 23, minute: 59))
        let next = try engine.day(on: date("1988-02-16", hour: 0))
        #expect(start == late)
        #expect(start.dayGanZhi == CalendarEngine().dayGanZhi(for: date("1988-02-15")))
        #expect(start.dayGanZhi != next.dayGanZhi)
        #expect(start.hours[0].ganZhi != start.hours[12].ganZhi)
        #expect(start.hours[12].ganZhi == next.hours[0].ganZhi)
        #expect(start.hours[12].yi == next.hours[0].yi)
        #expect(start.boundaryNote.contains("23:00"))
    }

    @Test func testHourRowsCoverOneCivilDateExactlyAndDoNotOverlap() throws {
        let value = try AlmanacEngine.shared.day(on: date("2026-09-17"))
        #expect(value.hours.count == 13)
        #expect(value.hours.first?.startMinute == 0)
        #expect(value.hours.last?.endMinute == 1440)
        #expect(value.hours.first?.label == "早子时")
        #expect(value.hours.last?.timeRange == "23:00–24:00")
        for (before, after) in zip(value.hours, value.hours.dropFirst()) {
            #expect(before.endMinute == after.startMinute)
        }
        for h in 0..<24 {
            let found = try AlmanacEngine.shared.hour(at: date("2026-09-17", hour: h, minute: 59))
            #expect(found.startMinute <= h * 60 + 59)
            #expect(found.endMinute > h * 60 + 59)
        }
    }

    @Test func testStarBoardsContainAllNineDistinctPalacesAndNumbers() throws {
        let value = try AlmanacEngine.shared.day(on: date("2026-12-22"))
        for star in [value.yearNineStar, value.monthNineStar, value.dayNineStar] + value.hours.map(\.nineStar) {
            #expect(star.palaces.count == 9)
            #expect(Set(star.palaces.map(\.palace)).count == 9)
            #expect(Set(star.palaces.map(\.number)).count == 9)
            #expect(star.palaces.first?.number == star.number)
        }
    }

    @Test func testUncoveredAndNonfiniteDatesFailExplicitly() throws {
        #expect(throws: AlmanacError.unsupportedYear) { try AlmanacEngine.shared.day(on: date("1900-12-31")) }
        #expect(throws: AlmanacError.unsupportedYear) { try AlmanacEngine.shared.hour(at: date("2100-01-01")) }
        #expect(throws: AlmanacError.invalidInstant) { try AlmanacEngine.shared.day(on: Date(timeIntervalSince1970: .nan)) }
        #expect(throws: AlmanacError.invalidInstant) { try AlmanacEngine.shared.day(on: Date(timeIntervalSince1970: .infinity)) }
    }

    @Test func testConcurrentCacheReadsPublishOnlyCompleteValues() async throws {
        let dates = ["1901-01-01", "2025-08-12", "2026-02-04", "2099-12-31"]
        try await withThrowingTaskGroup(of: AlmanacDay.self) { group in
            for input in dates + dates {
                let instant = date(input)
                group.addTask { try AlmanacEngine.shared.day(on: instant) }
            }
            for try await result in group {
                #expect(result.hours.count == 13)
                #expect(result.positions.count == 5)
                #expect(result.sourceLabel.contains("1.1.8"))
            }
        }
    }

    private struct Reference: Decodable {
        let source: String
        let dependency: String
        let cases: [Case]
    }
    private struct Case: Decodable {
        let date: String
        let day: Day
        let positions: [String: Position]
        let stars: [String: String]
        let hours: [Hour]
    }
    private struct Position: Decodable { let raw: String?; let desc: String }
    private struct Day: Decodable {
        let yi, ji, jiShen, xiongSha: [String]
        let tianShen, tianShenType, chongDesc, sha, luck: String
    }
    private struct Hour: Decodable {
        let hour: Int
        let ganZhi: String
        let yi, ji: [String]
        let tianShen, tianShenType, tianShenLuck, chongDesc, sha, star: String
        let positions: [String: Position]
    }
}
