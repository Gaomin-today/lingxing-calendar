import Foundation
import Testing
@testable import LingxiCore

struct BirthProfileCompatibilityTests {
    /// Literal v0.3 shape: neither v0.4 optional field existed in the archive.
    private let legacyJSON = #"{"id":"9D37B80D-2454-461B-96D9-AEA5E1B52483","name":"旧版合成档案","birthYear":1988,"birthMonth":2,"birthDay":15,"birthHour":23,"birthMinute":30,"birthTimeKnown":true,"timeZoneIdentifier":"Asia/Shanghai","birthplace":"测试备注","dayBoundary":"ziHour23"}"#

    @Test func legacyArchiveWithoutOptionalFieldsRemainsReadableAndPreservesBirthInstant() throws {
        let profile = try JSONDecoder().decode(BirthProfile.self, from: Data(legacyJSON.utf8))
        #expect(profile.luckGender == nil)
        #expect(profile.strengthAssumption == nil)
        #expect(profile.name == "旧版合成档案")
        #expect(profile.birthplace == "测试备注")
        #expect(profile.dayBoundary == .ziHour23)
        #expect(try profile.resolvedBirthDate() == ISO8601DateFormatter().date(from: "1988-02-15T15:30:00Z"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("profiles.json")
        try Data("[\(legacyJSON)]".utf8).write(to: file)
        #expect(try BirthProfileRepository(fileURL: file).load() == [profile])
    }

    @Test func newOptionalValuesRoundTripWithoutChangingCalendarMeaning() throws {
        let original = try JSONDecoder().decode(BirthProfile.self, from: Data(legacyJSON.utf8))
        let genders: [LuckGender?] = [nil, .male, .female]
        let assumptions: [BaziStrengthAssumption?] = [nil, .unspecified, .strong, .weak]
        for gender in genders {
            for assumption in assumptions {
                var profile = original
                profile.luckGender = gender
                profile.strengthAssumption = assumption
                let encoded = try JSONEncoder().encode(profile)
                let decoded = try JSONDecoder().decode(BirthProfile.self, from: encoded)
                #expect(decoded == profile)
                #expect(try decoded.resolvedBirthDate() == original.resolvedBirthDate())
                #expect(decoded.dayBoundary == original.dayBoundary)
            }
        }
    }

    @Test func explicitNullOptionalValuesAlsoRemainUnknown() throws {
        let text = String(legacyJSON.dropLast()) + #", "luckGender":null,"strengthAssumption":null}"#
        let profile = try JSONDecoder().decode(BirthProfile.self, from: Data(text.utf8))
        #expect(profile.luckGender == nil)
        #expect(profile.strengthAssumption == nil)
    }
}
