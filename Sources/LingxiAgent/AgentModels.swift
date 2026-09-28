import Foundation
import LingxiCore

/// The amount of work an Agent may perform for one user turn.
public enum AgentMode: String, Codable, Equatable, Hashable, Sendable {
    case quick
    case deep
}

public struct AgentBudget: Codable, Equatable, Sendable {
    public var maxReadRounds: Int
    public var maxToolCalls: Int
    public var maxModelCalls: Int
    public var timeoutSeconds: TimeInterval

    public init(maxReadRounds: Int = 2, maxToolCalls: Int = 6, maxModelCalls: Int = 4,
                timeoutSeconds: TimeInterval = 30) {
        // These are hard safety ceilings for the first runtime. Callers can
        // choose a smaller budget, but configuration cannot create an
        // unbounded loop.
        self.maxReadRounds = min(2, max(1, maxReadRounds))
        self.maxToolCalls = min(6, max(1, maxToolCalls))
        self.maxModelCalls = min(4, max(1, maxModelCalls))
        self.timeoutSeconds = timeoutSeconds.isFinite ? min(120, max(0.1, timeoutSeconds)) : 30
    }

    public static let quick = AgentBudget(maxReadRounds: 1, maxToolCalls: 4, maxModelCalls: 2, timeoutSeconds: 20)
    public static let deep = AgentBudget(maxReadRounds: 2, maxToolCalls: 6, maxModelCalls: 4, timeoutSeconds: 30)
}

public struct AgentRequest: Codable, Equatable, Sendable {
    public var requestID: String
    public var text: String
    public var mode: AgentMode?
    public var sessionID: String?
    public var submittedAt: Date

    public init(requestID: String = UUID().uuidString, text: String, mode: AgentMode? = nil,
                sessionID: String? = nil, submittedAt: Date = Date()) {
        self.requestID = requestID
        self.text = text
        self.mode = mode
        self.sessionID = sessionID
        self.submittedAt = submittedAt
    }
}

public enum AgentPhase: String, Codable, Equatable, Hashable, Sendable {
    case classify
    case loadSkill
    case planEvidence
    case retrieve
    case draft
    case deterministicCheck
    case critic
    case repair
    case final
    case failed
    case cancelled
}

public struct AgentStatus: Codable, Equatable, Sendable {
    public var phase: AgentPhase
    public var message: String
    public var completed: Bool

    public init(phase: AgentPhase, message: String, completed: Bool = false) {
        self.phase = phase
        self.message = message
        self.completed = completed
    }
}

public enum EvidenceType: String, Codable, Equatable, Hashable, Sendable {
    case deterministicFact
    case knowledgeText
    case userInput
    case modelInference
}

public struct EvidenceRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { claimID }
    public var claimID: String
    public var claim: String
    public var sourceRef: String
    public var sourceRevision: String?
    public var retrievedAt: Date
    public var evidenceType: EvidenceType
    public var confidence: Double
    public var conflictSet: [String]
    public var loopStep: Int

    public init(claimID: String = UUID().uuidString, claim: String, sourceRef: String,
                sourceRevision: String? = nil, retrievedAt: Date = Date(),
                evidenceType: EvidenceType, confidence: Double = 1,
                conflictSet: [String] = [], loopStep: Int = 0) {
        self.claimID = claimID
        self.claim = claim
        self.sourceRef = sourceRef
        self.sourceRevision = sourceRevision
        self.retrievedAt = retrievedAt
        self.evidenceType = evidenceType
        self.confidence = min(1, max(0, confidence))
        self.conflictSet = conflictSet
        self.loopStep = loopStep
    }
}

public struct EvidenceLedger: Codable, Equatable, Sendable {
    public private(set) var records: [EvidenceRecord]

    public init(records: [EvidenceRecord] = []) { self.records = records }

    public mutating func append(_ record: EvidenceRecord) {
        guard !record.claim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !record.sourceRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        records.append(record)
    }

    public mutating func append(contentsOf values: [EvidenceRecord]) { values.forEach { append($0) } }
    public var sourceCount: Int { Set(records.map(\.sourceRef)).count }
    public func record(for claimID: String) -> EvidenceRecord? { records.first { $0.claimID == claimID } }
    public func records(for sourceRef: String) -> [EvidenceRecord] { records.filter { $0.sourceRef == sourceRef } }
}

public struct AgentClaim: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var sourceRef: String?
    public var sourceRevision: String?
    public var evidenceType: EvidenceType
    public var confidence: Double

    public init(id: String = UUID().uuidString, text: String, sourceRef: String? = nil,
                sourceRevision: String? = nil, evidenceType: EvidenceType = .modelInference,
                confidence: Double = 0.5) {
        self.id = id
        self.text = text
        self.sourceRef = sourceRef
        self.sourceRevision = sourceRevision
        self.evidenceType = evidenceType
        self.confidence = min(1, max(0, confidence))
    }
}

public struct AgentCriticReport: Codable, Equatable, Sendable {
    public var passed: Bool
    public var missingEvidence: [String]
    public var conflicts: [String]
    public var staleSources: [String]
    public var unsupportedClaims: [String]
    public var needsSupplementalRead: Bool

    public init(passed: Bool = true, missingEvidence: [String] = [], conflicts: [String] = [],
                staleSources: [String] = [], unsupportedClaims: [String] = [], needsSupplementalRead: Bool = false) {
        self.passed = passed
        self.missingEvidence = missingEvidence
        self.conflicts = conflicts
        self.staleSources = staleSources
        self.unsupportedClaims = unsupportedClaims
        self.needsSupplementalRead = needsSupplementalRead
    }
}

public struct AgentAnswer: Codable, Equatable, Sendable {
    public var conclusion: String
    public var evidence: [EvidenceRecord]
    public var interpretation: String
    public var actions: [String]
    public var uncertainty: [String]
    public var mode: AgentMode
    public var degraded: Bool
    public var critic: AgentCriticReport

    public init(conclusion: String, evidence: [EvidenceRecord] = [], interpretation: String = "",
                actions: [String] = [], uncertainty: [String] = [], mode: AgentMode,
                degraded: Bool = false, critic: AgentCriticReport = .init()) {
        self.conclusion = conclusion
        self.evidence = evidence
        self.interpretation = interpretation
        self.actions = actions
        self.uncertainty = uncertainty
        self.mode = mode
        self.degraded = degraded
        self.critic = critic
    }
}

public struct AgentRunResult: Codable, Equatable, Sendable {
    public var requestID: String
    public var answer: AgentAnswer
    public var ledger: EvidenceLedger
    public var traceID: String
    public var statuses: [AgentStatus]
    public var quality: AgentQualityReport?

    public init(requestID: String, answer: AgentAnswer, ledger: EvidenceLedger, traceID: String,
                statuses: [AgentStatus] = [], quality: AgentQualityReport? = nil) {
        self.requestID = requestID
        self.answer = answer
        self.ledger = ledger
        self.traceID = traceID
        self.statuses = statuses
        self.quality = quality
    }
}

public enum AgentRuntimeError: Error, LocalizedError, Equatable, Sendable {
    case emptyRequest
    case cancelled
    case timeout
    case budgetExceeded
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyRequest: return "请输入要咨询的内容。"
        case .cancelled: return "已停止本次解读。"
        case .timeout: return "本次解读已到时间上限。"
        case .budgetExceeded: return "本次解读已达到读取或模型调用上限。"
        case .unavailable(let message): return message
        }
    }
}
