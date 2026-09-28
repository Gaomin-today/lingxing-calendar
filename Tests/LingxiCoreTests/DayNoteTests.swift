import Foundation
import Testing
@testable import LingxiCore

struct DayNoteTests {
    private func note(date: String = "2026-09-17") -> DayNote {
        DayNote(date: date, title: "准备明天的面试", body: "先核对地点，再整理案例。",
                createdAt: Date(timeIntervalSince1970: 1_789_646_400.123))
    }

    @Test func calendarDatesAreStrictAndIndependentOfBirthOrComputerTimeZone() throws {
        for valid in ["1901-01-01", "2000-02-29", "2024-02-29", "2099-12-31", "1949-05-28"] {
            try note(date: valid).validate()
        }
        for invalid in ["1900-12-31", "2100-01-01", "2026-02-29", "2026-04-31", "2026-00-17",
                        "2026-13-17", "2026-09-00", "2026-09-32", "2026-9-17", "26-09-17",
                        "２０２６-０９-１７", "2026-09-17T00:00:00Z", "2026-09-17\n", ""] {
            #expect(throws: DayNoteError.invalidDate) { try note(date: invalid).validate() }
        }
        #expect(DayNote.calendarTimeZoneIdentifier == "Asia/Shanghai")
    }

    @Test func invalidTextAndReversedTimestampsAreRejected() throws {
        var value = note()
        value.title = " \n\t"
        #expect(throws: DayNoteError.invalidTitle) { try value.validate() }
        value = note()
        value.title = String(repeating: "日", count: 121)
        #expect(throws: DayNoteError.invalidTitle) { try value.validate() }
        value = note()
        value.body = String(repeating: "日", count: 100_001)
        #expect(throws: DayNoteError.invalidBody) { try value.validate() }
        value = note()
        value.body = "\n"
        #expect(throws: DayNoteError.invalidBody) { try value.validate() }
        value = note()
        value.author = " "
        #expect(throws: DayNoteError.invalidAuthor) { try value.validate() }
        value = note()
        value.updatedAt = value.createdAt.addingTimeInterval(-1)
        #expect(throws: DayNoteError.invalidTimestamps) { try value.validate() }
    }

    @Test func strengthAssessmentRequiresExplicitAgentAnalysisAndVersionedProfile() throws {
        var value = note()
        #expect(value.strengthAssessment == nil)
        value.strengthAssessment = .strong
        #expect(throws: DayNoteError.invalidStrengthAssessment) { try value.validate() }
        value.kind = .insight
        value.source = .agent
        #expect(throws: DayNoteError.invalidStrengthAssessment) { try value.validate() }
        value.profileID = UUID()
        #expect(throws: DayNoteError.invalidStrengthAssessment) { try value.validate() }
        value.profileRevision = "revision-at-analysis"
        try value.validate()
        value.strengthAssessment = .unspecified
        try value.validate()
        value.source = .user
        #expect(throws: DayNoteError.invalidStrengthAssessment) { try value.validate() }
        value.strengthAssessment = nil
        value.profileID = nil
        #expect(throws: DayNoteError.invalidProfileRevision) { try value.validate() }
    }

    @Test func notesRoundTripWithoutAnUnstatedAssessmentOrAuthor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = DayNoteRepository(fileURL: directory.appendingPathComponent("nested/notes.json"))
        #expect(try repository.load().isEmpty)
        let original = note()
        try repository.save([original])
        #expect(try repository.load() == [original])
        #expect(try repository.load().first?.strengthAssessment == nil)
        #expect(try repository.load().first?.author == nil)
        #expect(DayNoteRepository.defaultURL().lastPathComponent == "notes.json")
        try repository.save([])
        #expect(try repository.load().isEmpty)
    }

    @Test func corruptAndDuplicateArchivesCannotBeReplacedByEmptySave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = DayNoteRepository(fileURL: directory.appendingPathComponent("notes.json"))
        let value = note()
        for original in [Data("not notes".utf8), try JSONEncoder().encode([value, value]),
                         try JSONEncoder().encode([note(date: "2026-02-30")])] {
            try original.write(to: repository.fileURL)
            #expect(throws: (any Error).self) { try repository.load() }
            #expect(throws: (any Error).self) { try repository.save([]) }
            #expect(try Data(contentsOf: repository.fileURL) == original)
        }
    }

    @Test func invalidNewNoteAndFailedSaveLeaveExistingArchiveIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = DayNoteRepository(fileURL: directory.appendingPathComponent("notes.json"))
        let value = note()
        try repository.save([value])
        let original = try Data(contentsOf: repository.fileURL)
        #expect(throws: DayNoteError.duplicateIdentifiers) { try repository.save([value, value]) }
        #expect(throws: DayNoteError.invalidDate) { try repository.save([note(date: "2026-02-30")]) }
        #expect(try Data(contentsOf: repository.fileURL) == original)
        let blocked = DayNoteRepository(fileURL: repository.fileURL.appendingPathComponent("child.json"))
        #expect(throws: (any Error).self) { try blocked.save([value]) }
        #expect(try Data(contentsOf: repository.fileURL) == original)
    }
}
