import Foundation
import Testing
@testable import LingxiCore

struct BirthProfileTests {
    private func known(
        year: Int = 1997, month: Int = 1, day: Int = 15,
        hour: Int = 14, minute: Int = 20, zone: String = "Asia/Shanghai"
    ) -> BirthProfile {
        BirthProfile(name: "测试档案", birthYear: year, birthMonth: month,
                     birthDay: day, birthHour: hour, birthMinute: minute,
                     birthTimeKnown: true, timeZoneIdentifier: zone)
    }

    private func utc(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    @Test func knownTimeResolvesInTheRecordedZone() throws {
        let profile = known()
        #expect(try profile.resolvedBirthDate() == utc("1997-01-15T06:20:00Z"))
        #expect(try profile.referenceBirthDate() == profile.resolvedBirthDate())
        #expect(try profile.isBirthTimeAmbiguous() == false)
    }

    @Test func civilDateValidationDoesNotNormalizeInvalidDays() throws {
        try known(year: 2000, month: 2, day: 29).validate()
        for invalid in [known(year: 2001, month: 2, day: 29), known(month: 2, day: 30),
                        known(month: 4, day: 31), known(month: 0), known(month: 13),
                        known(day: 0), known(day: 32)] {
            #expect(throws: BirthProfileError.invalidDate) { try invalid.validate() }
        }
    }

    @Test func supportedRangeAndKnownClockComponentsAreStrict() throws {
        try known(year: 1901, month: 1, day: 1).validate()
        try known(year: 2099, month: 12, day: 31).validate()
        for year in [Int.min, 1900, 2100, Int.max] {
            #expect(throws: BirthProfileError.yearOutOfRange) { try known(year: year).validate() }
        }
        for invalid in [known(hour: -1), known(hour: 24), known(minute: -1), known(minute: 60)] {
            #expect(throws: BirthProfileError.invalidTime) { try invalid.validate() }
        }
    }

    @Test func unknownTimeIsNotResolvedAndIgnoresStoredClockPlaceholders() throws {
        var profile = known()
        profile.birthTimeKnown = false
        profile.birthHour = Int.max
        profile.birthMinute = Int.min
        #expect(try profile.resolvedBirthDate() == nil)
        #expect(try profile.referenceBirthDate() == utc("1997-01-15T04:00:00Z"))
        #expect(try profile.isBirthTimeAmbiguous() == false)
        profile.birthDay = 32
        #expect(throws: BirthProfileError.invalidDate) { try profile.resolvedBirthDate() }
    }

    @Test func timezoneValidationAcceptsIANAIdentifiersAndLinksWithoutOffsetGuessing() throws {
        for zone in ["Asia/Shanghai", "America/New_York", "US/Eastern", "UTC", "Etc/UTC", "Etc/GMT+8"] {
            try known(zone: zone).validate()
        }
        for zone in ["", "Not/A_Zone", "上海", "PST", "GMT+0800", "UTC+08:00", " Asia/Shanghai "] {
            #expect(throws: BirthProfileError.invalidTimeZone) { try known(zone: zone).validate() }
        }
    }

    @Test func nonexistentKnownTimeIsRejectedInsteadOfShiftedByDST() {
        let gap = known(year: 2024, month: 3, day: 10, hour: 2, minute: 30, zone: "America/New_York")
        #expect(throws: BirthProfileError.nonexistentLocalTime) { try gap.resolvedBirthDate() }
    }

    @Test func repeatedClockTimeUsesTheFirstOccurrenceAndReportsAmbiguity() throws {
        let fold = known(year: 2024, month: 11, day: 3, hour: 1, minute: 30, zone: "America/New_York")
        #expect(try fold.resolvedBirthDate() == utc("2024-11-03T05:30:00Z"))
        #expect(try fold.isBirthTimeAmbiguous())
        #expect(BirthProfile.repeatedTimePolicyDescription.contains("第一次"))
    }

    @Test func halfHourFoldIsDetectedWithoutAssumingOneHourDST() throws {
        let fold = known(year: 2024, month: 4, day: 7, hour: 1, minute: 45, zone: "Australia/Lord_Howe")
        #expect(try fold.resolvedBirthDate() == utc("2024-04-06T14:45:00Z"))
        #expect(try fold.isBirthTimeAmbiguous())
    }

    @Test func unknownBirthDateRejectsAWhollySkippedCivilDay() {
        var skipped = known(year: 2011, month: 12, day: 30, zone: "Pacific/Apia")
        skipped.birthTimeKnown = false
        #expect(throws: BirthProfileError.nonexistentLocalDate) { try skipped.referenceBirthDate() }
    }

    @Test func unknownTimeCanUseAReferenceOnAnOtherwiseValidNoonGapDay() throws {
        var profile = known(year: 2000, month: 1, day: 15, hour: 12, minute: 0, zone: "Africa/Juba")
        #expect(throws: BirthProfileError.nonexistentLocalTime) { try profile.resolvedBirthDate() }
        profile.birthTimeKnown = false
        #expect(try profile.resolvedBirthDate() == nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try profile.validatedTimeZone()
        let reference = try profile.referenceBirthDate()
        #expect(calendar.component(.day, from: reference) == 15)
        #expect(calendar.component(.hour, from: reference) == 13)
    }

    @Test func birthplaceAndChartDayBoundaryDoNotChangeTheBirthInstant() throws {
        var profile = known(hour: 23, minute: 30)
        let actual = try profile.resolvedBirthDate()
        profile.birthplace = "出生地备注，不用于经度修正"
        profile.dayBoundary = .ziHour23
        #expect(try profile.resolvedBirthDate() == actual)
        #expect(BirthDayBoundary.midnight.rawValue == "midnight")
        #expect(BirthDayBoundary.ziHour23.rawValue == "ziHour23")
    }

    @Test func profileRepositoryRoundTripsAndUsesASeparateFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = BirthProfileRepository(fileURL: directory.appendingPathComponent("nested/profiles.json"))
        #expect(try repository.load().isEmpty)
        var second = BirthProfile(name: "时刻未知", birthYear: 2000, birthMonth: 2, birthDay: 29)
        second.birthplace = "备注"
        second.dayBoundary = .ziHour23
        let profiles = [known(), second]
        try repository.save(profiles)
        #expect(try BirthProfileRepository(fileURL: repository.fileURL).load() == profiles)
        let stored = try String(contentsOf: repository.fileURL, encoding: .utf8)
        #expect(stored.contains("ziHour23"))
        #expect(!stored.contains("gender"))
        #expect(BirthProfileRepository.defaultURL().lastPathComponent == "profiles.json")
        #expect(BirthProfileRepository.defaultURL() != EventRepository.defaultURL())
        try repository.save([])
        #expect(try repository.load().isEmpty)
    }

    @Test func corruptProfileFileCannotBeOverwrittenByAnEmptySave() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let original = Data("not birth profiles".utf8)
        try original.write(to: file)
        let repository = BirthProfileRepository(fileURL: file)
        #expect(throws: (any Error).self) { try repository.load() }
        #expect(throws: (any Error).self) { try repository.save([]) }
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func invalidNewProfileCannotReplaceValidStoredProfiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = BirthProfileRepository(fileURL: directory.appendingPathComponent("profiles.json"))
        let profile = known()
        try repository.save([profile])
        let original = try Data(contentsOf: repository.fileURL)
        #expect(throws: BirthProfileError.invalidDate) { try repository.save([known(month: 2, day: 30)]) }
        #expect(throws: BirthProfileError.duplicateIdentifiers) { try repository.save([profile, profile]) }
        #expect(try Data(contentsOf: repository.fileURL) == original)
    }

    @Test func invalidDecodedProfilesAreNotSilentlyRepairedOrReplaced() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let original = try JSONEncoder().encode([known(month: 2, day: 30)])
        try original.write(to: file)
        let repository = BirthProfileRepository(fileURL: file)
        #expect(throws: BirthProfileError.invalidDate) { try repository.load() }
        #expect(throws: BirthProfileError.invalidDate) { try repository.save([]) }
        #expect(try Data(contentsOf: file) == original)
    }
}
