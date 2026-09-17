import Foundation
import Testing
@testable import LingxiCore

struct CalendarTests {
    private let engine = CalendarEngine()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        engine.gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func testChineseNewYearAndMidAutumnMatchHKO() {
        let examples = [
            (2025, 1, 29, "正月初一", "春节", "乙巳", "蛇"),
            (2025, 10, 6, "八月十五", "中秋节", "乙巳", "蛇"),
            (2026, 2, 17, "正月初一", "春节", "丙午", "马"),
            (2026, 9, 25, "八月十五", "中秋节", "丙午", "马"),
            (2027, 2, 6, "正月初一", "春节", "丁未", "羊"),
            (2027, 9, 15, "八月十五", "中秋节", "丁未", "羊")
        ]
        for (year, month, day, lunar, festival, ganZhi, zodiac) in examples {
            let input = date(year, month, day)
            let info = engine.info(for: input)
            #expect(info.lunarDate == lunar)
            #expect(info.yearGanZhi == ganZhi)
            #expect(info.zodiac == zodiac)
            #expect(engine.festivals(on: input).contains { $0.name == festival })
        }
    }

    @Test func testYearChangesAtChineseNewYearNotLichun() {
        #expect(engine.info(for: date(2026, 2, 4)).yearGanZhi == "乙巳")
        #expect(engine.info(for: date(2026, 2, 16, hour: 23, minute: 59)).yearGanZhi == "乙巳")
        #expect(engine.info(for: date(2026, 2, 17, hour: 0)).yearGanZhi == "丙午")
    }

    @Test func testLeapSixthMonthAndNoDuplicateObservance() {
        let first = engine.info(for: date(2025, 7, 25))
        #expect(first.lunarDate == "闰六月初一")
        #expect(first.isLeapMonth)
        #expect(first.numericLunarMonth == 6)
        #expect(first.numericLunarDay == 1)
        #expect(engine.festivals(on: date(2025, 7, 13)).contains { $0.id == "guanyin-enlightenment" })
        #expect(engine.info(for: date(2025, 8, 12)).lunarDate == "闰六月十九")
        #expect(engine.festivals(on: date(2025, 8, 12)).isEmpty)
        #expect(engine.info(for: date(2025, 8, 23)).lunarDate == "七月初一")
    }

    @Test func testSolarTermsMatchHKOIncludingYearDependentDates() {
        #expect(engine.solarTerm(on: date(2025, 2, 3)) == "立春")
        #expect(engine.solarTerm(on: date(2025, 2, 4)) == nil)
        #expect(engine.solarTerm(on: date(2025, 4, 4)) == "清明")
        #expect(engine.solarTerm(on: date(2026, 4, 5)) == "清明")
        #expect(engine.solarTerm(on: date(2026, 9, 7)) == "白露")
        #expect(engine.solarTerm(on: date(2026, 9, 23)) == "秋分")
        #expect(engine.solarTerm(on: date(2026, 12, 22)) == "冬至")
        #expect(engine.solarTerm(on: date(2027, 3, 6)) == "惊蛰")
        #expect(engine.solarTerm(on: date(2027, 9, 8)) == "白露")
    }

    @Test func testAllCoveredYearsHaveExactly24TermsAndUncoveredYearIsExplicit() {
        for year in CalendarEngine.solarTermSupportedYears {
            var day = date(year, 1, 1, hour: 0)
            let end = date(year + 1, 1, 1, hour: 0)
            var names: [String] = []
            while day < end {
                if let name = engine.solarTerm(on: day) { names.append(name) }
                day = engine.gregorian.date(byAdding: .day, value: 1, to: day)!
            }
            #expect(names.count == 24)
            #expect(Set(names).count == 24)
        }
        #expect(!(engine.hasSolarTermData(for: date(2028, 9, 7))))
        #expect(engine.solarTerm(on: date(2028, 9, 7)) == nil)
        #expect(engine.hasSolarTermData(for: date(2026, 9, 17)))
        #expect(engine.solarTerm(on: date(2026, 9, 17)) == nil)
    }

    @Test func testMonthGridIs42ContiguousDaysBeginningMonday() {
        for month in 1...12 {
            let days = engine.monthDays(containing: date(2026, month, 17))
            #expect(days.count == 42)
            #expect(engine.gregorian.component(.weekday, from: days[0]) == 2)
            #expect(Set(days).count == 42)
            #expect(days.contains(date(2026, month, 1, hour: 0)))
            for pair in zip(days, days.dropFirst()) {
                #expect(engine.gregorian.dateComponents([.day], from: pair.0, to: pair.1).day == 1)
            }
        }
        #expect(engine.monthDays(containing: date(2026, 9, 17)).first == date(2026, 8, 31, hour: 0))
        #expect(engine.monthDays(containing: date(2026, 6, 17)).first == date(2026, 6, 1, hour: 0))
    }

    @Test func testBeijingMidnightBoundaryEvenWhenInputIsUTC() {
        let iso = ISO8601DateFormatter()
        let before = iso.date(from: "2026-02-16T15:59:59Z")!
        let after = iso.date(from: "2026-02-16T16:00:00Z")!
        #expect(engine.info(for: before).lunarDate == "腊月廿九")
        #expect(engine.info(for: after).lunarDate == "正月初一")
        #expect(engine.festivals(on: after).contains { $0.id == "spring-festival" })
    }

    @Test func testDayGanZhiAgainstHKO2010MarchPage() {
        // HKO's March page: lunar 1/16 庚戌 (March 1), 1/30 甲子 (March 15),
        // lunar 2/1 乙丑 (March 16), lunar 2/15 己卯 (March 30).
        #expect(engine.dayGanZhi(for: date(2010, 3, 1)) == "庚戌")
        #expect(engine.dayGanZhi(for: date(2010, 3, 15)) == "甲子")
        #expect(engine.dayGanZhi(for: date(2010, 3, 16)) == "乙丑")
        #expect(engine.dayGanZhi(for: date(2010, 3, 30)) == "己卯")
        #expect(engine.dayGanZhi(for: date(2010, 3, 14, hour: 23, minute: 59)) == "癸亥")
        #expect(engine.dayGanZhi(for: date(2010, 3, 15, hour: 0)) == "甲子")
    }

    @Test func testCatalogHasSpecificSourcesAndUniqueIDs() throws {
        #expect(Set(FestivalCatalog.all.map(\.id)).count == FestivalCatalog.all.count)
        #expect(FestivalCatalog.all.filter { $0.kind == "神诞" }.count >= 3)
        for item in FestivalCatalog.all {
            #expect(!(item.region.isEmpty))
            #expect(!(item.sourceTitle.isEmpty))
            #expect(URL(string: item.sourceURL)?.scheme == "https")
            #expect((1...12).contains(item.lunarMonth))
            #expect((1...30).contains(item.lunarDay))
        }
        let data = try JSONEncoder().encode(FestivalCatalog.all)
        #expect(try JSONDecoder().decode([Festival].self, from: data) == FestivalCatalog.all)
    }

    @Test func testSourcedDeityDatesResolveToTheir2026CivilDates() {
        let examples = [
            (2, 25, "jade-emperor"), (3, 21, "man-cheung"),
            (4, 6, "guanyin-birthday"), (4, 19, "pak-tai"),
            (5, 9, "tin-hau"), (8, 1, "guanyin-enlightenment")
        ]
        for (month, day, id) in examples {
            #expect(engine.festivals(on: date(2026, month, day)).contains { $0.id == id })
        }
    }
}
