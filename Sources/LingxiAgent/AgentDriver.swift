import Foundation
import LingxiCore

public enum AgentMessageRole: String, Codable, Equatable, Hashable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct AgentMessage: Codable, Equatable, Sendable {
    public var role: AgentMessageRole
    public var content: String
    public var name: String?

    public init(role: AgentMessageRole, content: String, name: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
    }
}

public struct AgentModelRequest: Codable, Equatable, Sendable {
    public var requestID: String
    public var step: Int
    public var mode: AgentMode
    public var messages: [AgentMessage]
    public var context: AgentPromptContext

    public init(requestID: String, step: Int, mode: AgentMode, messages: [AgentMessage], context: AgentPromptContext) {
        self.requestID = requestID
        self.step = step
        self.mode = mode
        self.messages = messages
        self.context = context
    }
}

public struct AgentToolCall: Codable, Equatable, Sendable {
    public var id: String
    public var name: AgentToolName
    public var arguments: [String: JSONValue]

    public init(id: String = UUID().uuidString, name: AgentToolName, arguments: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct AgentModelResponse: Codable, Equatable, Sendable {
    public var text: String?
    public var toolCalls: [AgentToolCall]
    public var claims: [AgentClaim]
    public var finished: Bool
    public var critic: AgentCriticReport?

    public init(text: String? = nil, toolCalls: [AgentToolCall] = [], claims: [AgentClaim] = [],
                finished: Bool = true, critic: AgentCriticReport? = nil) {
        self.text = text
        self.toolCalls = toolCalls
        self.claims = claims
        self.finished = finished
        self.critic = critic
    }
}

/// Model-facing abstraction. A production adapter may implement Chat Completions,
/// Responses, or a local model without exposing transport details to the runtime.
public protocol ModelGateway: Sendable {
    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse
}

/// Alias protocol kept as the extension point for experimental external drivers.
public protocol AgentDriver: ModelGateway {}

public struct ClosureModelGateway: ModelGateway {
    private let body: @Sendable (AgentModelRequest) async throws -> AgentModelResponse

    public init(_ body: @escaping @Sendable (AgentModelRequest) async throws -> AgentModelResponse) {
        self.body = body
    }

    public func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        try await body(request)
    }
}
