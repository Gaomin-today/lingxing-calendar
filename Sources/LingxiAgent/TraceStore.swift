import Foundation

public struct AgentTraceEvent: Codable, Equatable, Sendable {
    public var phase: AgentPhase
    public var at: Date
    public var summary: String
    public var toolName: AgentToolName?
    public var sourceRefs: [String]
    public var success: Bool

    public init(phase: AgentPhase, at: Date = Date(), summary: String, toolName: AgentToolName? = nil,
                sourceRefs: [String] = [], success: Bool = true) {
        self.phase = phase
        self.at = at
        self.summary = String(summary.prefix(500))
        self.toolName = toolName
        self.sourceRefs = Array(sourceRefs.prefix(20))
        self.success = success
    }
}

public struct AgentTrace: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var requestID: String
    public var mode: AgentMode
    public var model: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var events: [AgentTraceEvent]
    public var toolCalls: Int
    public var modelCalls: Int
    public var loopRounds: Int
    public var critic: AgentCriticReport?
    public var degraded: Bool
    public var failure: String?

    public init(id: String = UUID().uuidString, requestID: String, mode: AgentMode, model: String? = nil,
                startedAt: Date = Date(), endedAt: Date? = nil, events: [AgentTraceEvent] = [],
                toolCalls: Int = 0, modelCalls: Int = 0, loopRounds: Int = 0, critic: AgentCriticReport? = nil,
                degraded: Bool = false, failure: String? = nil) {
        self.id = id; self.requestID = requestID; self.mode = mode; self.model = model
        self.startedAt = startedAt; self.endedAt = endedAt; self.events = Array(events.prefix(100))
        self.toolCalls = toolCalls; self.modelCalls = modelCalls; self.loopRounds = loopRounds; self.critic = critic
        self.degraded = degraded; self.failure = failure
    }

    public var duration: TimeInterval? { endedAt.map { max(0, $0.timeIntervalSince(startedAt)) } }
}

public actor TraceStore {
    private var values: [String: AgentTrace] = [:]
    private let maximumEntries: Int

    public init(maximumEntries: Int = 200) { self.maximumEntries = max(1, maximumEntries) }

    public func begin(requestID: String, mode: AgentMode, model: String? = nil, at: Date = Date()) -> AgentTrace {
        let trace = AgentTrace(requestID: requestID, mode: mode, model: model, startedAt: at)
        values[trace.id] = trace
        trim()
        return trace
    }

    public func append(_ event: AgentTraceEvent, to traceID: String) {
        guard var trace = values[traceID] else { return }
        guard trace.events.count < 100 else { return }
        trace.events.append(event)
        if event.toolName != nil { trace.toolCalls += 1 }
        if event.summary.hasPrefix("模型步骤") { trace.modelCalls += 1 }
        if event.phase == .retrieve && event.toolName == nil { trace.loopRounds += 1 }
        values[traceID] = trace
    }

    public func finish(_ traceID: String, critic: AgentCriticReport? = nil, degraded: Bool = false,
                       failure: String? = nil, at: Date = Date()) {
        guard var trace = values[traceID] else { return }
        trace.endedAt = at; trace.critic = critic; trace.degraded = degraded; trace.failure = failure.map { String($0.prefix(500)) }
        trace.loopRounds = max(trace.loopRounds, trace.events.filter { $0.phase == .retrieve && $0.toolName == nil }.count)
        values[traceID] = trace
    }

    public func trace(_ id: String) -> AgentTrace? { values[id] }
    public func latest(requestID: String) -> AgentTrace? {
        values.values.filter { $0.requestID == requestID }.max {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id < $1.id
        }
    }
    public func all() -> [AgentTrace] { values.values.sorted { $0.startedAt < $1.startedAt } }
    public func remove(_ id: String) { values.removeValue(forKey: id) }
    public func removeAll() { values.removeAll() }

    private func trim() {
        guard values.count > maximumEntries else { return }
        let count = values.count - maximumEntries
        for id in values.values.sorted(by: { $0.startedAt < $1.startedAt }).prefix(count).map(\.id) { values.removeValue(forKey: id) }
    }
}
