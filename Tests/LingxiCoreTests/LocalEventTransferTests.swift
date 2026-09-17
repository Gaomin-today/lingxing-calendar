import Foundation
import Testing
@testable import LingxiCore

struct LocalEventTransferTests {
    private enum Failure: Error, Equatable {
        case creation, removal, rollback
    }

    @Test func successfulTransferCreatesBeforeRemovingAndIsIdempotent() {
        let transfer = LocalEventTransfer<String>()
        let localID = UUID()
        var localExists = true
        var systemRecords: Set<String> = []
        var calls: [String] = []
        let outcome = transfer.transfer(localID: localID, create: {
            calls.append("create")
            #expect(localExists)
            systemRecords.insert("system-record")
            return "system-record"
        }, removeLocal: {
            calls.append("remove")
            #expect(systemRecords.contains("system-record"))
            localExists = false
        }, rollback: { receipt in
            calls.append("rollback")
            systemRecords.remove(receipt)
        })
        guard case .saved(let receipt) = outcome else { Issue.record("Expected a saved transfer"); return }
        #expect(receipt == "system-record")
        #expect(!localExists)
        #expect(systemRecords == ["system-record"])
        #expect(calls == ["create", "remove"])
        #expect(transfer.pendingReceipt(for: localID) == nil)
        #expect(transfer.completedReceipt(for: localID) == receipt)

        let repeated = transfer.transfer(localID: localID, create: {
            calls.append("duplicate-create")
            return "other-record"
        }, removeLocal: { calls.append("duplicate-remove") }, rollback: { _ in calls.append("duplicate-rollback") })
        guard case .saved(let repeatedReceipt) = repeated else { Issue.record("Expected the original success"); return }
        #expect(repeatedReceipt == receipt)
        #expect(calls == ["create", "remove"])
    }

    @Test func creationFailurePreservesLocalAndCanBeRetried() {
        let transfer = LocalEventTransfer<String>()
        let localID = UUID()
        var calls: [String] = []
        let failed = transfer.transfer(localID: localID, create: {
            calls.append("failed-create")
            throw Failure.creation
        }, removeLocal: { calls.append("remove") }, rollback: { _ in calls.append("rollback") })
        guard case .failed(let stage, let error) = failed else { Issue.record("Expected a creation failure"); return }
        #expect(stage == .creation)
        #expect(error as? Failure == .creation)
        #expect(calls == ["failed-create"])
        #expect(transfer.pendingTransfers.isEmpty)
        #expect(transfer.completedReceipt(for: localID) == nil)

        let retried = transfer.transfer(localID: localID, create: {
            calls.append("create")
            return "receipt"
        }, removeLocal: { calls.append("remove") }, rollback: { _ in calls.append("rollback") })
        guard case .saved = retried else { Issue.record("Expected retry to save"); return }
        #expect(calls == ["failed-create", "create", "remove"])
    }

    @Test func localFailureRollsBackAndNewAttemptOnlyCreatesAfterCompensation() {
        let transfer = LocalEventTransfer<String>()
        let localID = UUID()
        var localExists = true
        var systemRecords: Set<String> = []
        var calls: [String] = []
        let failed = transfer.transfer(localID: localID, create: {
            calls.append("create-first")
            systemRecords.insert("first")
            return "first"
        }, removeLocal: {
            calls.append("failed-remove")
            throw Failure.removal
        }, rollback: { receipt in
            calls.append("rollback-\(receipt)")
            systemRecords.remove(receipt)
        })
        guard case .failed(let stage, let error) = failed else { Issue.record("Expected compensated failure"); return }
        #expect(stage == .localRemoval)
        #expect(error as? Failure == .removal)
        #expect(systemRecords.isEmpty)
        #expect(localExists)
        #expect(transfer.pendingTransfers.isEmpty)
        #expect(calls == ["create-first", "failed-remove", "rollback-first"])

        let retry = transfer.transfer(localID: localID, create: {
            #expect(systemRecords.isEmpty)
            calls.append("create-second")
            systemRecords.insert("second")
            return "second"
        }, removeLocal: { calls.append("remove"); localExists = false }, rollback: { receipt in systemRecords.remove(receipt) })
        guard case .saved(let receipt) = retry else { Issue.record("Expected new compensated attempt to save"); return }
        #expect(receipt == "second")
        #expect(!localExists)
        #expect(systemRecords == ["second"])
        #expect(calls == ["create-first", "failed-remove", "rollback-first", "create-second", "remove"])
    }

    @Test func failedRollbackRetainsReceiptAndRetriesOnlyLocalCleanup() {
        let transfer = LocalEventTransfer<String>()
        let localID = UUID()
        var localExists = true
        var systemRecords: Set<String> = []
        var creations = 0
        var removals = 0
        var rollbacks = 0
        let first = transfer.transfer(localID: localID, create: {
            creations += 1
            systemRecords.insert("retained-receipt")
            return "retained-receipt"
        }, removeLocal: {
            removals += 1
            throw Failure.removal
        }, rollback: { receipt in
            #expect(receipt == "retained-receipt")
            rollbacks += 1
            throw Failure.rollback
        })
        guard case .pendingCleanup(let receipt, let cleanupError, let rollbackError) = first else {
            Issue.record("Expected a recoverable receipt"); return
        }
        #expect(receipt == "retained-receipt")
        #expect(cleanupError as? Failure == .removal)
        #expect(rollbackError as? Failure == .rollback)
        #expect(transfer.pendingReceipt(for: localID) == receipt)
        #expect(transfer.pendingTransfers == [localID: receipt])

        let stillPending = transfer.transfer(localID: localID, create: {
            creations += 1
            systemRecords.insert("wrong-destination")
            return "wrong-destination"
        }, removeLocal: { removals += 1; throw Failure.removal }, rollback: { _ in rollbacks += 1 })
        guard case .pendingCleanup(let preservedReceipt, _, let preservedError) = stillPending else {
            Issue.record("Expected a retryable cleanup failure"); return
        }
        #expect(preservedReceipt == receipt)
        #expect(preservedError as? Failure == .rollback)
        #expect(localExists)
        #expect(systemRecords == [receipt])
        #expect(creations == 1)
        #expect(removals == 2)
        #expect(rollbacks == 1)

        let recovered = transfer.transfer(localID: localID, create: {
            creations += 1
            return "duplicate"
        }, removeLocal: { removals += 1; localExists = false }, rollback: { _ in rollbacks += 1 })
        guard case .saved(let recoveredReceipt) = recovered else { Issue.record("Expected successful cleanup"); return }
        #expect(recoveredReceipt == receipt)
        #expect(!localExists)
        #expect(systemRecords == [receipt])
        #expect(transfer.pendingTransfers.isEmpty)
        #expect(creations == 1)
        #expect(removals == 3)
        #expect(rollbacks == 1)
    }

    @Test func missingSystemReceiptDuringRetryKeepsSurvivingLocalCopy() {
        let transfer = LocalEventTransfer<String>()
        let id = UUID()
        var localExists = true
        var systemExists = false
        var creations = 0
        transfer.transfer(localID: id, create: {
            creations += 1; systemExists = true; return "receipt"
        }, removeLocal: { throw Failure.removal }, rollback: { _ in throw Failure.rollback })
        // The system copy is deleted in another app before cleanup is retried.
        systemExists = false
        let retried = transfer.transfer(localID: id, create: {
            creations += 1; return "duplicate"
        }, removeLocal: {
            guard systemExists else { throw Failure.removal }
            localExists = false
        }, rollback: { _ in Issue.record("Pending recovery must not roll back again") })
        guard case .pendingCleanup = retried else { Issue.record("Expected local copy to remain protected"); return }
        #expect(localExists)
        #expect(creations == 1)
        #expect(transfer.completedReceipt(for: id) == nil)
        #expect(transfer.pendingReceipt(for: id) == "receipt")
    }

    @Test func pendingTransferDoesNotBlockOrReuseAnotherLocalUUID() {
        let transfer = LocalEventTransfer<String>()
        let firstID = UUID(), secondID = UUID()
        var created: [String] = []
        transfer.transfer(localID: firstID, create: {
            created.append("first")
            return "first"
        }, removeLocal: { throw Failure.removal }, rollback: { _ in throw Failure.rollback })

        let second = transfer.transfer(localID: secondID, create: {
            created.append("second")
            return "second"
        }, removeLocal: {}, rollback: { _ in Issue.record("Second record should not be rolled back") })
        guard case .saved(let receipt) = second else { Issue.record("Expected independent success"); return }
        #expect(receipt == "second")
        #expect(created == ["first", "second"])
        #expect(transfer.pendingTransfers == [firstID: "first"])
        #expect(transfer.pendingReceipt(for: secondID) == nil)
    }
}
