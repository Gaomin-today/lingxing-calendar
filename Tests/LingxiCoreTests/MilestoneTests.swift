import Foundation
import Testing
@testable import LingxiCore

struct MilestoneTests {
    private let engine = MilestoneEngine()
    private func date(_ text: String) throws -> Date { try engine.civilDate(text) }
    private func profile(_ year: Int = 1990, _ month: Int = 6, _ day: Int = 15, tracking: BirthdayTracking? = nil) -> BirthProfile {
        BirthProfile(name: "合成生日", birthYear: year, birthMonth: month, birthDay: day, birthdayTracking: tracking)
    }

    @Test func oneTimeCountdownAndAnniversaryCoverFutureTodayAndPast() throws {
        var item = Milestone(title: "合成出发日", targetDate: "2026-09-20")
        let before = try engine.occurrence(for: item, on: date("2026-09-18"))
        #expect(before.daysDelta == 2 && before.status == .upcoming)
        #expect(before.headline == "还有 2 天")
        let at = try engine.occurrence(for: item, on: date("2026-09-20"))
        #expect(at.daysDelta == 0 && at.status == .today)
        #expect(at.headline == "就是今天")
        let past = try engine.occurrence(for: item, on: date("2026-09-22"))
        #expect(past.daysDelta == -2 && past.headline == "已过 2 天")
        item.kind = .anniversary
        #expect(try engine.occurrence(for: item, on: date("2026-09-22")).headline == "已经 2 天")
        #expect(try engine.occurrence(for: item, on: date("2026-09-20")).headline == "纪念日就在今天")
    }

    @Test func annualDatesIncludeTodayAndRollForwardWithoutBackdatingOrigin() throws {
        var item = Milestone(title: "合成纪念日", kind: .anniversary, targetDate: "2020-09-20", repeatsAnnually: true)
        #expect(try engine.occurrence(for: item, on: date("2026-09-20")).targetDate == "2026-09-20")
        #expect(try engine.occurrence(for: item, on: date("2026-09-21")).targetDate == "2027-09-20")
        item.targetDate = "2030-09-20"
        #expect(try engine.occurrence(for: item, on: date("2026-09-21")).targetDate == "2030-09-20")
    }

    @Test func gregorianLeapDayPolicyIsExplicitForMilestonesAndBirthdays() throws {
        let item = Milestone(title: "合成闰日", targetDate: "2024-02-29", repeatsAnnually: true)
        let regular = try engine.occurrence(for: item, on: date("2026-02-01"))
        #expect(regular.targetDate == "2026-02-28")
        #expect(regular.ruleNote?.contains("2 月 28 日") == true)
        #expect(try engine.occurrence(for: item, on: date("2028-02-01")).targetDate == "2028-02-29")
        let birthday = try #require(try engine.birthday(for: profile(2000, 2, 29, tracking: .solar), on: date("2026-02-28")))
        #expect(birthday.daysDelta == 0 && birthday.status == .today)
        #expect(birthday.detail.contains("非闰年"))
    }

    @Test func birthdayTrackingIsOptInAndIndependentOfUnknownBirthHour() throws {
        let value = profile()
        #expect(try engine.birthday(for: value, on: date("2026-09-18")) == nil)
        var selected = value; selected.birthdayTracking = .solar
        #expect(!selected.birthTimeKnown)
        let occurrence = try #require(try engine.birthday(for: selected, on: date("2026-09-18")))
        #expect(occurrence.targetDate == "2027-06-15")
        #expect(occurrence.source == .birthday)
        #expect(try engine.birthday(for: selected, on: date("1989-01-01")) == nil)
    }

    @Test func lunarNewYearBirthdayUsesLunarInsteadOfGregorianAnniversary() throws {
        // Synthetic 2000-02-05 is lunar first month/day 1.
        let value = profile(2000, 2, 5, tracking: .lunar)
        let next = try #require(try engine.birthday(for: value, on: date("2026-01-01")))
        #expect(next.targetDate == "2026-02-17")
        #expect(next.detail.contains("农历正月初一"))
        let rolled = try #require(try engine.birthday(for: value, on: date("2026-02-18")))
        #expect(rolled.targetDate == "2027-02-06")
    }

    @Test func leapLunarBirthdayPrefersSameLeapMonthAndOtherwiseOrdinaryMonth() throws {
        // Synthetic 2023-03-22 is leap second month/day 1. 2042 next has leap 2.
        let value = profile(2023, 3, 22, tracking: .lunar)
        let fallback = try #require(try engine.birthday(for: value, on: date("2026-01-01")))
        #expect(fallback.targetDate == "2026-03-19")
        #expect(fallback.detail.contains("无对应闰月"))
        #expect(fallback.detail.contains("农历闰二月初一"))
        #expect(!fallback.detail.contains("闰闰"))
        let matching = try #require(try engine.birthday(for: value, on: date("2042-01-01")))
        #expect(matching.targetDate == "2042-03-22")
        #expect(!matching.detail.contains("无对应闰月"))
    }

    @Test func lunarThirtiethInSmallMonthUsesLastDay() throws {
        // Synthetic 2000-02-04 is lunar twelfth month/day 29: create a known
        // thirtieth birth date instead, 1995-01-30 = 1994 lunar 12/30.
        let value = profile(1995, 1, 30, tracking: .lunar)
        let occurrence = try #require(try engine.birthday(for: value, on: date("2026-01-01")))
        #expect(occurrence.targetDate == "2026-02-16")
        #expect(occurrence.detail.contains("只有29日"))
        #expect(occurrence.detail.contains("农历腊月三十"))
    }

    @Test func naturalDayArithmeticSurvivesHistoricalShanghaiDST() throws {
        let item = Milestone(title: "合成夏令时", targetDate: "1990-04-16")
        #expect(try engine.occurrence(for: item, on: date("1990-04-14")).daysDelta == 2)
        let utc = ISO8601DateFormatter().date(from: "2026-09-18T16:01:00Z")!
        #expect(try engine.dateText(utc) == "2026-09-19")
    }

    @Test func validationRejectsMalformedOrOutOfRangeDatesAndUnboundedText() throws {
        for invalid in ["2026-02-30", "2026-9-18", "2026-09-18junk", "1900-01-01", "2100-01-01"] {
            #expect(throws: MilestoneError.invalidDate) { try Milestone(title: "合成", targetDate: invalid).validate() }
        }
        #expect(throws: MilestoneError.invalidTitle) { try Milestone(title: "  ", targetDate: "2026-09-18").validate() }
        #expect(throws: MilestoneError.invalidTitle) { try Milestone(title: String(repeating: "字", count: 81), targetDate: "2026-09-18").validate() }
        #expect(throws: MilestoneError.invalidNote) { try Milestone(title: "合成", targetDate: "2026-09-18", note: String(repeating: "字", count: 2001)).validate() }
        #expect(throws: MilestoneError.invalidDate) { try engine.dateText(Date(timeIntervalSince1970: .nan)) }
        let last = Milestone(title: "合成年底", targetDate: "2099-01-01", repeatsAnnually: true)
        #expect(throws: MilestoneError.noNextOccurrence) { try engine.occurrence(for: last, on: date("2099-12-31")) }
    }

    @Test func orderingPlacesTodayThenUpcomingBeforeMostRecentPast() throws {
        let entries = try ["2026-09-10", "2026-09-22", "2026-09-18", "2026-09-17"].map {
            try engine.occurrence(for: Milestone(title: $0, targetDate: $0), on: date("2026-09-18"))
        }
        #expect(MilestoneEngine.sorted(entries).map(\.daysDelta) == [0, 4, -1, -8])
    }

    @Test func corruptStorageIsPreservedAndDuplicateIDsAreRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("milestones.json")
        let repository = MilestoneRepository(fileURL: file)
        let item = Milestone(title: "合成存储", targetDate: "2026-09-18")
        try repository.save([item]); #expect(try repository.load() == [item])
        #expect(throws: MilestoneError.duplicateIdentifiers) { try repository.save([item, item]) }
        #expect(try repository.load() == [item])
        let bad = Data("{not-an-array".utf8); try bad.write(to: file)
        #expect(throws: (any Error).self) { try repository.save([]) }
        #expect(try Data(contentsOf: file) == bad)
    }

    @Test func birthdayPreferencePreservesLegacyAnalysisIdentityButChangesFullRevision() throws {
        let legacy = profile()
        #expect(try legacy.analysisRevision() == AutomationSnapshot.revision(legacy))
        var enabled = legacy; enabled.birthdayTracking = .solar
        var lunar = legacy; lunar.birthdayTracking = .lunar
        #expect(try enabled.analysisRevision() == legacy.analysisRevision())
        #expect(try lunar.analysisRevision() == legacy.analysisRevision())
        #expect(try AutomationSnapshot.revision(enabled) != AutomationSnapshot.revision(legacy))
        #expect(try AutomationSnapshot.revision(lunar) != AutomationSnapshot.revision(enabled))
        var birthChanged = enabled; birthChanged.birthMinute += 1
        #expect(try birthChanged.analysisRevision() != enabled.analysisRevision())
        let encoded = try JSONEncoder().encode(enabled)
        #expect(try JSONDecoder().decode(BirthProfile.self, from: encoded) == enabled)
        let legacyEncoded = try JSONEncoder().encode(legacy)
        #expect(!String(decoding: legacyEncoded, as: UTF8.self).contains("birthdayTracking"))
        #expect(try JSONDecoder().decode(BirthProfile.self, from: legacyEncoded).birthdayTracking == nil)
    }
}
