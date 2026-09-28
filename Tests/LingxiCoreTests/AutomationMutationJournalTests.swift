import Foundation
import Testing
@testable import LingxiCore

struct AutomationMutationJournalTests {
    private func plan(requestID: String = "meeting-2026-09-17", fingerprint: String = "request-fingerprint") throws -> AutomationMutationPlan {
        let desired = JSONValue.object(["id": .string(UUID().uuidString), "title": .string("面试前准备")])
        return AutomationMutationPlan(requestID: requestID, fingerprint: fingerprint, method: "events.create",
                                      entity: "events", entityID: UUID(), desired: desired,
                                      desiredRevision: try AutomationSnapshot.revision(desired),
                                      preparedAt: Date(timeIntervalSince1970: 1_789_646_400.123456))
    }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func canonicalSnapshotRevisionIgnoresObjectKeyInsertionOrder() throws {
        let left = JSONValue.object(["b": .number(2), "a": .string("日笺/资料")])
        let right = JSONValue.object(["a": .string("日笺/资料"), "b": .number(2)])
        let revision = try AutomationSnapshot.revision(left)
        #expect(try revision == AutomationSnapshot.revision(right))
        #expect(revision.count == 64)
        #expect(try revision != AutomationSnapshot.revision(JSONValue.object(["a": .string("changed"), "b": .number(2)])))
    }

    @Test func preparedPlanSurvivesRestartAndRetryUsesOriginalEntityAndTimestamps() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("receipts.json")
        var journal = try AutomationMutationJournal(fileURL: file)
        let original = try plan()
        let prepared = try journal.prepare(original)
        #expect(prepared.state == .prepared)
        #expect(prepared.result == nil)
        var restarted = try AutomationMutationJournal(fileURL: file)
        let newlyGenerated = try plan()
        #expect(newlyGenerated.entityID != original.entityID)
        let retried = try restarted.prepare(newlyGenerated)
        #expect(retried == prepared)
        #expect(restarted.records.count == 1)
        #expect(retried.entityID == original.entityID)
        #expect(retried.desired == original.desired)
    }

    @Test func completedRequestReturnsOriginalResultEvenAfterRestart() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("receipts.json")
        var journal = try AutomationMutationJournal(fileURL: file)
        let prepared = try journal.prepare(plan())
        let result = JSONValue.object(["id": .string(prepared.entityID.uuidString), "saved": .bool(true)])
        let completed = try journal.complete(requestID: prepared.requestID, fingerprint: prepared.fingerprint, result: result)
        #expect(completed.state == .completed)
        #expect(completed.result == result)
        var restarted = try AutomationMutationJournal(fileURL: file)
        let repeated = try restarted.complete(requestID: prepared.requestID, fingerprint: prepared.fingerprint, result: .null)
        #expect(repeated == completed)
        #expect(try restarted.prepare(plan()) == completed)
        #expect(restarted.records.count == 1)
    }

    @Test func reusedRequestIDWithDifferentFingerprintIsRejectedBeforeAnyWrite() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("receipts.json")
        var journal = try AutomationMutationJournal(fileURL: file)
        let original = try journal.prepare(plan())
        let bytes = try Data(contentsOf: file)
        #expect(throws: AutomationMutationJournalError.requestIDConflict) {
            try journal.prepare(plan(fingerprint: "different-content"))
        }
        #expect(throws: AutomationMutationJournalError.requestIDConflict) {
            try journal.complete(requestID: original.requestID, fingerprint: "different-content", result: .null)
        }
        #expect(throws: AutomationMutationJournalError.missingRequest) {
            try journal.complete(requestID: "never-prepared", fingerprint: "fingerprint", result: .null)
        }
        #expect(try Data(contentsOf: file) == bytes)
        #expect(journal.records == [original])
    }

    @Test func invalidPlansAndTamperedDesiredRevisionsAreRejected() throws {
        var value = try plan()
        value.requestID = " "
        #expect(throws: AutomationMutationJournalError.invalidRequestID) { try value.validate() }
        value.requestID = String(repeating: "a", count: 129)
        #expect(throws: AutomationMutationJournalError.invalidRequestID) { try value.validate() }
        value = try plan()
        value.entity = "apple-events"
        #expect(throws: AutomationMutationJournalError.invalidEntity) { try value.validate() }
        value = try plan()
        value.desiredRevision = "does-not-match-snapshot"
        #expect(throws: AutomationMutationJournalError.invalidPlan) { try value.validate() }
        value.desired = nil
        #expect(throws: AutomationMutationJournalError.invalidPlan) { try value.validate() }
        value.desiredRevision = nil
        try value.validate() // A deletion has no desired snapshot or revision.
    }

    @Test func corruptOrDuplicateReceiptArchivesCannotInitializeOrBeOverwritten() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("receipts.json")
        var journal = try AutomationMutationJournal(fileURL: file)
        let value = try plan()
        for original in [Data("not mutation receipts".utf8), try AutomationJSON.encode([value, value])] {
            try original.write(to: file)
            #expect(throws: (any Error).self) { try AutomationMutationJournal(fileURL: file) }
            #expect(throws: (any Error).self) { try journal.prepare(value) }
            #expect(try Data(contentsOf: file) == original)
            #expect(journal.records.isEmpty)
        }
    }

    @Test func failedPrepareAndCompleteDoNotAdvanceMemory() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockedParent = directory.appendingPathComponent("blocked-parent")
        try Data("file, not a directory".utf8).write(to: blockedParent)
        var blocked = try AutomationMutationJournal(fileURL: blockedParent.appendingPathComponent("receipts.json"))
        #expect(throws: (any Error).self) { try blocked.prepare(plan()) }
        #expect(blocked.records.isEmpty)

        let file = directory.appendingPathComponent("receipts.json")
        var journal = try AutomationMutationJournal(fileURL: file)
        let prepared = try journal.prepare(plan())
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) {
            try journal.complete(requestID: prepared.requestID, fingerprint: prepared.fingerprint, result: .bool(true))
        }
        #expect(journal.records == [prepared])
        #expect(journal.records.first?.state == .prepared)
    }

    @Test func staleWriterCannotEraseAnotherPreparedReceipt() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("receipts.json")
        var first = try AutomationMutationJournal(fileURL: file)
        var stale = try AutomationMutationJournal(fileURL: file)
        let prepared = try first.prepare(plan())
        #expect(throws: AutomationMutationJournalError.concurrentModification) {
            try stale.prepare(plan(requestID: "another-operation"))
        }
        #expect(try AutomationMutationJournal(fileURL: file).records == [prepared])
        #expect(stale.records.isEmpty)
    }

    @Test func backwardsClockStillAllowsCompletionAndSubmillisecondTimesStayConsistent() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var journal = try AutomationMutationJournal(fileURL: directory.appendingPathComponent("receipts.json"))
        let prepared = try journal.prepare(plan())
        let result = try journal.complete(requestID: prepared.requestID, fingerprint: prepared.fingerprint,
                                          result: .null, at: prepared.preparedAt.addingTimeInterval(-300))
        #expect(result.completedAt == prepared.preparedAt)
        #expect(result.result == .null)
        #expect(try AutomationMutationJournal(fileURL: journal.fileURL).records == journal.records)
        _ = try journal.prepare(plan(requestID: "next-write"))
        #expect(journal.records.count == 2)
    }
}
