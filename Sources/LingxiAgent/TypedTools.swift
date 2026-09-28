import Foundation
import LingxiCore

/// The only tools a first-party Agent may request. There is intentionally no
/// path, shell, database, EventKit, or arbitrary-code tool in this enum.
public enum AgentToolName: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case profileContext = "profile_context"
    case chartContext = "chart_context"
    case dayContext = "day_context"
    case eventsContext = "events_context"
    case notesContext = "notes_context"
    case knowledgeSearch = "knowledge_search"
    case knowledgeRead = "knowledge_read"
    case conversationContext = "conversation_context"
}

public struct AgentToolResult: Codable, Equatable, Sendable {
    public var callID: String
    public var name: AgentToolName
    public var payload: JSONValue
    public var sourceRef: String
    public var sourceRevision: String?
    public var retrievedAt: Date
    public var evidenceType: EvidenceType

    public init(callID: String, name: AgentToolName, payload: JSONValue, sourceRef: String,
                sourceRevision: String? = nil, retrievedAt: Date = Date(),
                evidenceType: EvidenceType = .deterministicFact) {
        self.callID = callID
        self.name = name
        self.payload = payload
        self.sourceRef = sourceRef
        self.sourceRevision = sourceRevision
        self.retrievedAt = retrievedAt
        self.evidenceType = evidenceType
    }
}

public struct AgentToolError: Error, LocalizedError, Equatable, Sendable {
    public var name: AgentToolName
    public var message: String
    public init(name: AgentToolName, message: String) { self.name = name; self.message = message }
    public var errorDescription: String? { message }
}

public protocol ReadOnlyToolProvider: Sendable {
    func read(_ call: AgentToolCall) async throws -> AgentToolResult
}

/// A registry with an explicit allowlist and bounded response size. Adapters
/// in LingxiApp can map these calls to AppAutomationRouter without making this
/// target depend on SwiftUI or an application store.
public struct TypedToolRegistry: Sendable {
    public typealias Handler = @Sendable (AgentToolCall) async throws -> AgentToolResult
    private final class ProviderBox: @unchecked Sendable {
        let provider: any ReadOnlyToolProvider
        init(_ provider: any ReadOnlyToolProvider) { self.provider = provider }
    }
    private let handlers: [AgentToolName: Handler]
    public let maximumPayloadCharacters: Int

    public init(handlers: [AgentToolName: Handler] = [:], maximumPayloadCharacters: Int = 40_000) {
        self.handlers = handlers
        self.maximumPayloadCharacters = max(1, maximumPayloadCharacters)
    }

    public init(provider: any ReadOnlyToolProvider, maximumPayloadCharacters: Int = 40_000) {
        let box = ProviderBox(provider)
        var handlers: [AgentToolName: Handler] = [:]
        for name in AgentToolName.allCases {
            let handler: Handler = { call in try await box.provider.read(call) }
            handlers[name] = handler
        }
        self.init(handlers: handlers, maximumPayloadCharacters: maximumPayloadCharacters)
    }

    public var availableTools: Set<AgentToolName> { Set(handlers.keys) }

    public func read(_ call: AgentToolCall) async throws -> AgentToolResult {
        guard let handler = handlers[call.name] else {
            throw AgentToolError(name: call.name, message: "工具未开放：\(call.name.rawValue)。")
        }
        let result = try await handler(call)
        let encoded = try AutomationJSON.encode(result.payload)
        guard encoded.count <= maximumPayloadCharacters else {
            throw AgentToolError(name: call.name, message: "工具返回内容超过本次上下文上限。")
        }
        guard result.name == call.name else {
            throw AgentToolError(name: call.name, message: "工具返回的名称与请求不一致。")
        }
        guard result.callID == call.id else {
            throw AgentToolError(name: call.name, message: "工具返回的 call_id 与请求不一致。")
        }
        guard Self.validMetadata(result.sourceRef, maximumBytes: 256),
              result.sourceRevision.map({ Self.validMetadata($0, maximumBytes: 256) }) ?? true else {
            throw AgentToolError(name: call.name, message: "工具返回的来源标识无效。")
        }
        return result
    }

    private static func validMetadata(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes &&
            value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}

public struct InMemoryToolProvider: ReadOnlyToolProvider {
    private let values: [AgentToolName: AgentToolResult]
    public init(values: [AgentToolName: AgentToolResult]) { self.values = values }
    public func read(_ call: AgentToolCall) async throws -> AgentToolResult {
        guard let value = values[call.name] else { throw AgentToolError(name: call.name, message: "没有可用的模拟工具结果。") }
        return AgentToolResult(callID: call.id, name: value.name, payload: value.payload, sourceRef: value.sourceRef,
                               sourceRevision: value.sourceRevision, retrievedAt: value.retrievedAt, evidenceType: value.evidenceType)
    }
}
