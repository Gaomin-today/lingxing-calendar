import Foundation

/// Citation checks only establish that a statement points to the exact data
/// read in this run. A matching citation does not prove the statement's meaning.
public enum AgentClaimCitationStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case cited = "引用匹配"
    case missingSource = "缺少来源"
    case sourceNotFound = "来源未读取"
    case missingRevision = "缺少声明版本"
    case sourceRevisionMissing = "来源缺少版本"
    case staleRevision = "版本不匹配"
    case typeMismatch = "来源类型不符"
    case conflictingRevisions = "来源版本冲突"
    case modelInference = "模型推断，不计引用覆盖"
    case userInput = "用户输入，不计引用覆盖"
}

public struct AgentClaimAssessment: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let claim: AgentClaim
    public let status: AgentClaimCitationStatus
    public var isCited: Bool { status == .cited }

    public init(id: String, claim: AgentClaim, status: AgentClaimCitationStatus) {
        self.id = id
        self.claim = claim
        self.status = status
    }

    public var countsTowardCoverage: Bool {
        claim.evidenceType == .deterministicFact || claim.evidenceType == .knowledgeText
    }
}

/// Only the model's explicitly structured fact/knowledge claims form the
/// denominator. Tool reads and the ledger's generic source entries never do.
/// Nil coverage means there were no structured factual claims to measure;
/// prose outside `claims` has not been assessed and is not treated as verified.
public struct AgentQualityReport: Codable, Equatable, Sendable {
    public let claims: [AgentClaimAssessment]
    public var factClaimCount: Int { claims.filter(\.countsTowardCoverage).count }
    public var citedFactCount: Int { claims.filter { $0.countsTowardCoverage && $0.isCited }.count }
    public var citationCoverage: Double? {
        let total = factClaimCount
        return total == 0 ? nil : Double(citedFactCount) / Double(total)
    }

    public init(claims: [AgentClaimAssessment]) { self.claims = claims }

    public static func evaluate(claims: [AgentClaim], references: [AgentToolResult]) -> AgentQualityReport {
        let bySource = Dictionary(grouping: references, by: \.sourceRef)
        let assessments = claims.enumerated().map { index, claim in
            // Model-provided IDs are not guaranteed to be unique. Including
            // the input index makes UI identities stable within this report.
            AgentClaimAssessment(id: "\(index):\(claim.id)", claim: claim,
                                 status: assess(claim, bySource: bySource))
        }
        return AgentQualityReport(claims: assessments)
    }

    private static func assess(_ claim: AgentClaim,
                               bySource: [String: [AgentToolResult]]) -> AgentClaimCitationStatus {
        switch claim.evidenceType {
        case .modelInference: return .modelInference
        case .userInput: return .userInput
        case .deterministicFact, .knowledgeText: break
        }
        guard let source = nonempty(claim.sourceRef) else { return .missingSource }
        guard let matches = bySource[source], !matches.isEmpty else { return .sourceNotFound }
        guard let revision = nonempty(claim.sourceRevision) else { return .missingRevision }
        let versions = Set(matches.map { nonempty($0.sourceRevision) })
        // Unknown and known revisions together are also ambiguous: no read
        // may be silently picked as the authoritative version.
        guard versions.count == 1 else { return .conflictingRevisions }
        guard let actual = nonempty(matches[0].sourceRevision) else { return .sourceRevisionMissing }
        guard actual == revision else { return .staleRevision }
        guard matches.allSatisfy({ $0.evidenceType == claim.evidenceType }) else { return .typeMismatch }
        return .cited
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // Whitespace is checked for emptiness, not normalized for matching.
        return value
    }
}
