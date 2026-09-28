import Foundation
import LingxiCore

/// A write proposed by the Agent after an explicit user request. The runtime
/// never executes this value; AppStore presents it and the user confirms it.
public struct AgentActionProposal: Codable, Equatable, Identifiable, Sendable {
    public var id: String { request.requestID ?? "" }
    public var kind: String
    public var title: String
    public var summary: String
    public var request: AutomationRequest

    public init(kind: String, title: String, summary: String, request: AutomationRequest) {
        self.kind = kind
        self.title = title
        self.summary = summary
        self.request = request
    }
}

/// The receipt returned by the existing router after a verified local write.
/// `revision` is used to build the one-step undo request without guessing at
/// the current record state.
public struct AgentActionReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: String { requestID }
    public var requestID: String
    public var method: String
    public var entity: String
    public var entityID: String
    public var revision: String?

    public init(requestID: String, method: String, entity: String, entityID: String, revision: String?) {
        self.requestID = requestID
        self.method = method
        self.entity = entity
        self.entityID = entityID
        self.revision = revision
    }
}
