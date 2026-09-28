import CryptoKit
import Foundation

/// Snapshot versions and mutation fingerprints share the protocol's canonical
/// key ordering. Callers must keep using the same domain snapshot shape when
/// comparing an expected version with the current or desired version.
public enum AutomationSnapshot {
    public static func revision<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try AutomationJSON.encode(value)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum AutomationMutationState: String, Codable, Sendable {
    case prepared, completed
}

public enum AutomationMutationJournalError: Error, LocalizedError, Equatable, Sendable {
    case invalidRequestID, invalidFingerprint, invalidMethod, invalidEntity, invalidPlan
    case duplicateRequestIDs, requestIDConflict, missingRequest, concurrentModification

    public var errorDescription: String? {
        switch self {
        case .invalidRequestID: return "写入 request_id 不能为空、含空白或控制字符，且不能超过 128 个 UTF-8 字节。"
        case .invalidFingerprint: return "写入请求指纹无效。"
        case .invalidMethod: return "写入操作名称无效。"
        case .invalidEntity: return "写入凭据仅支持本地日程、档案和日笺。"
        case .invalidPlan: return "写入计划状态或快照无效，已保留原凭据。"
        case .duplicateRequestIDs: return "写入凭据包含重复 request_id，已保留原文件。"
        case .requestIDConflict: return "这个 request_id 已用于不同内容，请为新的操作使用新的 request_id。"
        case .missingRequest: return "尚未持久化这个写入计划，不能标记为完成。"
        case .concurrentModification: return "写入凭据已被其他实例修改，请重新加载后重试。"
        }
    }
}

/// Persist the desired snapshot before touching the domain store. A retry uses
/// this exact plan, including its original UUID and timestamps. The caller is
/// responsible for checking current == expected or current == desired before
/// applying it. This journal does not transact with EventKit or external stores.
public struct AutomationMutationPlan: Codable, Equatable, Sendable {
    public var requestID: String
    public var fingerprint: String
    public var method: String
    public var entity: String
    public var entityID: UUID
    public var expectedRevision: String?
    public var desired: JSONValue?
    public var desiredRevision: String?
    public private(set) var result: JSONValue?
    public private(set) var state: AutomationMutationState
    public var preparedAt: Date
    public private(set) var completedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case requestID, fingerprint, method, entity, entityID, expectedRevision
        case desired, desiredRevision, result, state, preparedAt, completedAt
    }

    public init(
        requestID: String, fingerprint: String, method: String, entity: String,
        entityID: UUID, expectedRevision: String? = nil, desired: JSONValue? = nil,
        desiredRevision: String? = nil, preparedAt: Date = Date()
    ) {
        self.requestID = requestID
        self.fingerprint = fingerprint
        self.method = method
        self.entity = entity
        self.entityID = entityID
        self.expectedRevision = expectedRevision
        self.desired = desired
        self.desiredRevision = desiredRevision
        self.preparedAt = preparedAt
        self.state = .prepared
        self.result = nil
        self.completedAt = nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(String.self, forKey: .requestID)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        method = try container.decode(String.self, forKey: .method)
        entity = try container.decode(String.self, forKey: .entity)
        entityID = try container.decode(UUID.self, forKey: .entityID)
        expectedRevision = try container.decodeIfPresent(String.self, forKey: .expectedRevision)
        desiredRevision = try container.decodeIfPresent(String.self, forKey: .desiredRevision)
        // Missing means no snapshot/result; explicit JSON null remains a value.
        desired = container.contains(.desired) ? try container.decode(JSONValue.self, forKey: .desired) : nil
        result = container.contains(.result) ? try container.decode(JSONValue.self, forKey: .result) : nil
        state = try container.decode(AutomationMutationState.self, forKey: .state)
        preparedAt = try container.decode(Date.self, forKey: .preparedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    public func validate() throws {
        guard Self.validToken(requestID, maximumBytes: 128) else { throw AutomationMutationJournalError.invalidRequestID }
        guard Self.validToken(fingerprint, maximumBytes: 256) else { throw AutomationMutationJournalError.invalidFingerprint }
        guard Self.validToken(method, maximumBytes: 128) else { throw AutomationMutationJournalError.invalidMethod }
        guard ["events", "profiles", "notes"].contains(entity) else { throw AutomationMutationJournalError.invalidEntity }
        if let expectedRevision, !Self.validToken(expectedRevision, maximumBytes: 256) {
            throw AutomationMutationJournalError.invalidPlan
        }
        if let desiredRevision, !Self.validToken(desiredRevision, maximumBytes: 256) {
            throw AutomationMutationJournalError.invalidPlan
        }
        guard (desired == nil) == (desiredRevision == nil), preparedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AutomationMutationJournalError.invalidPlan
        }
        if let desired {
            guard try AutomationSnapshot.revision(desired) == desiredRevision else {
                throw AutomationMutationJournalError.invalidPlan
            }
        }
        switch state {
        case .prepared:
            guard result == nil, completedAt == nil else { throw AutomationMutationJournalError.invalidPlan }
        case .completed:
            guard result != nil, let completedAt, completedAt.timeIntervalSinceReferenceDate.isFinite,
                  completedAt >= preparedAt else { throw AutomationMutationJournalError.invalidPlan }
        }
    }

    fileprivate mutating func finish(result: JSONValue, at date: Date) {
        self.result = result
        self.state = .completed
        self.completedAt = date
    }

    private static func validToken(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes &&
            value.unicodeScalars.allSatisfy { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }
    }
}

/// Single-application-process mutation receipts. Corrupt archives throw during
/// initialization so the CLI can disable writes without discarding receipts.
/// Memory changes only after the atomic disk replacement succeeds. Receipts
/// are retained so an old completed request cannot silently execute again.
public struct AutomationMutationJournal: Sendable {
    public let fileURL: URL
    public private(set) var records: [AutomationMutationPlan]

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.records = try Self.load(from: fileURL)
    }

    public func record(requestID: String, fingerprint: String) throws -> AutomationMutationPlan? {
        guard let stored = records.first(where: { $0.requestID == requestID }) else { return nil }
        guard stored.fingerprint == fingerprint else { throw AutomationMutationJournalError.requestIDConflict }
        return stored
    }

    @discardableResult
    public mutating func prepare(_ plan: AutomationMutationPlan) throws -> AutomationMutationPlan {
        if let existing = try record(requestID: plan.requestID, fingerprint: plan.fingerprint) { return existing }
        try plan.validate()
        guard plan.state == .prepared else { throw AutomationMutationJournalError.invalidPlan }
        var updated = records
        updated.append(plan)
        try persist(updated)
        return records[records.count - 1]
    }

    @discardableResult
    public mutating func complete(
        requestID: String, fingerprint: String, result: JSONValue, at date: Date = Date()
    ) throws -> AutomationMutationPlan {
        guard let existing = try record(requestID: requestID, fingerprint: fingerprint),
              let index = records.firstIndex(where: { $0.requestID == requestID }) else {
            throw AutomationMutationJournalError.missingRequest
        }
        if existing.state == .completed { return existing }
        var updated = records
        // The wall clock may have moved backwards since the prepared write.
        updated[index].finish(result: result, at: max(date, existing.preparedAt))
        try persist(updated)
        return records[index]
    }

    public static func defaultURL() -> URL {
        EventRepository.defaultURL().deletingLastPathComponent().appendingPathComponent("automation-mutations.json", isDirectory: false)
    }

    private mutating func persist(_ updated: [AutomationMutationPlan]) throws {
        try Self.validate(updated)
        // Besides protecting corrupt files, reject stale in-memory writers.
        // All normal CLI operations are serialized in the application's actor.
        guard try Self.load(from: fileURL) == records else { throw AutomationMutationJournalError.concurrentModification }
        let data = try AutomationJSON.encode(updated)
        // Protocol dates have millisecond precision. Retain the exact decoded
        // snapshot, so the next disk comparison does not mistake the original
        // in-memory sub-millisecond timestamp for another writer's change.
        let normalized = try AutomationJSON.decode([AutomationMutationPlan].self, from: data)
        try Self.validate(normalized)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        records = normalized
    }

    private static func load(from url: URL) throws -> [AutomationMutationPlan] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let records = try AutomationJSON.decode([AutomationMutationPlan].self, from: Data(contentsOf: url))
        try validate(records)
        return records
    }

    private static func validate(_ records: [AutomationMutationPlan]) throws {
        guard Set(records.map(\.requestID)).count == records.count else {
            throw AutomationMutationJournalError.duplicateRequestIDs
        }
        for record in records { try record.validate() }
    }
}
