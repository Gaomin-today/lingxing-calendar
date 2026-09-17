import Foundation

/// Coordinates a system insert followed by local removal, with compensating
/// rollback if removal fails. Use from one serialized execution context.
///
/// Receipts are retained only for this coordinator's lifetime. Two independent
/// databases cannot provide an atomic transaction across a process crash; this
/// in-memory coordinator does not claim crash-safe exactly-once delivery.
/// Closures must report their committed outcome accurately: a thrown creation
/// error must not leave an unreported insert, and a thrown removal error must
/// leave the local record available for recovery.
public final class LocalEventTransfer<Receipt> {
    public enum FailureStage: Equatable {
        case creation
        case localRemoval
    }

    public enum Outcome {
        case saved(receipt: Receipt)
        case failed(stage: FailureStage, error: any Error)
        case pendingCleanup(receipt: Receipt, cleanupError: any Error, rollbackError: any Error)
    }

    private enum State {
        case saved(Receipt)
        case pending(Receipt, rollbackError: any Error)
    }

    private var states: [UUID: State] = [:]

    public init() {}

    /// Lets callers reject stale editors after the local record has disappeared.
    public func completedReceipt(for localID: UUID) -> Receipt? {
        guard case .saved(let receipt) = states[localID] else { return nil }
        return receipt
    }

    /// A pending receipt identifies the already-created system record. Callers
    /// must prevent editing the corresponding local record or changing its
    /// destination until cleanup succeeds, so a retry cannot discard new edits.
    public func pendingReceipt(for localID: UUID) -> Receipt? {
        guard case .pending(let receipt, _) = states[localID] else { return nil }
        return receipt
    }

    public var pendingTransfers: [UUID: Receipt] {
        states.compactMapValues { state in
            guard case .pending(let receipt, _) = state else { return nil }
            return receipt
        }
    }

    /// Retries of pending transfers only remove the local record; they never
    /// create or roll back again. Repeating an already successful transfer is
    /// a no-op returning its original receipt.
    @discardableResult
    public func transfer(
        localID: UUID,
        create: () throws -> Receipt,
        removeLocal: () throws -> Void,
        rollback: (Receipt) throws -> Void
    ) -> Outcome {
        if let state = states[localID] {
            switch state {
            case .saved(let receipt):
                return .saved(receipt: receipt)
            case .pending(let receipt, let rollbackError):
                do {
                    try removeLocal()
                    states[localID] = .saved(receipt)
                    return .saved(receipt: receipt)
                } catch {
                    return .pendingCleanup(receipt: receipt, cleanupError: error, rollbackError: rollbackError)
                }
            }
        }

        let receipt: Receipt
        do {
            receipt = try create()
        } catch {
            return .failed(stage: .creation, error: error)
        }
        do {
            try removeLocal()
            states[localID] = .saved(receipt)
            return .saved(receipt: receipt)
        } catch {
            let cleanupError = error
            do {
                try rollback(receipt)
                return .failed(stage: .localRemoval, error: cleanupError)
            } catch {
                states[localID] = .pending(receipt, rollbackError: error)
                return .pendingCleanup(receipt: receipt, cleanupError: cleanupError, rollbackError: error)
            }
        }
    }
}
