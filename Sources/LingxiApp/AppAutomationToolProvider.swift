import Foundation
import LingxiAgent
import LingxiCore

/// Bridges the Agent's small, typed read-only tool surface to the same
/// application router used by the local automation server. Keeping the
/// method mapping here makes it impossible for a model tool call to select a
/// Router method (and, in particular, a mutation) dynamically.
final class AppAutomationToolProvider: ReadOnlyToolProvider, @unchecked Sendable {
    private final class RouterBox: @unchecked Sendable {
        let router: AppAutomationRouter
        init(_ router: AppAutomationRouter) { self.router = router }
    }

    private let router: RouterBox
    private let cloudOnly: Bool

    init(router: AppAutomationRouter, cloudOnly: Bool = false) {
        self.router = RouterBox(router)
        self.cloudOnly = cloudOnly
    }

    var registry: TypedToolRegistry {
        var handlers: [AgentToolName: TypedToolRegistry.Handler] = [:]
        for name in Self.allowedTools(cloudOnly: cloudOnly) {
            handlers[name] = { [self] call in try await read(call) }
        }
        return TypedToolRegistry(handlers: handlers)
    }

    static func allowedTools(cloudOnly: Bool) -> Set<AgentToolName> {
        cloudOnly ? [.dayContext, .eventsContext] : Set(AgentToolName.allCases)
    }

    func read(_ call: AgentToolCall) async throws -> AgentToolResult {
        let request = try Self.request(for: call, cloudOnly: cloudOnly)
        let response = await router.router.handleAgentRead(request)
        guard response.ok else {
            let failure = response.error
            let message = [failure?.code, failure?.message]
                .compactMap { $0 }
                .joined(separator: ": ")
            throw AgentToolError(name: call.name, message: message.isEmpty ? "只读工具请求失败。" : message)
        }
        guard let payload = response.result else {
            throw AgentToolError(name: call.name, message: "只读工具没有返回内容。")
        }

        return try Self.result(for: call, request: request, payload: payload, cloudOnly: cloudOnly)
    }

    /// Pure response assembly makes the privacy boundary testable without
    /// creating an AppStore, touching its files, or asking EventKit for access.
    static func result(for call: AgentToolCall, request: AutomationRequest,
                       payload: JSONValue, cloudOnly: Bool) throws -> AgentToolResult {
        let output = cloudOnly ? try cloudProjection(payload, for: call.name) : payload
        // The local Router envelopes profiles, events and notes with their own
        // revisions. Do not hash the whole payload here: day/event reads may
        // contain a retrieval timestamp. Stable revisions are extracted from
        // the domain envelope when one is available.
        // Cloud references bind exactly what is shared, including empty sets.
        // Local revisions can cover private fields, so never reuse them here.
        let revision = cloudOnly ? try AutomationSnapshot.revision(output) : Self.revision(in: output)
        let parameterRevision = (try? AutomationSnapshot.revision(request.params)) ?? "current"
        let evidenceType: EvidenceType = {
            switch call.name {
            case .knowledgeSearch, .knowledgeRead: return .knowledgeText
            default: return .deterministicFact
            }
        }()
        return AgentToolResult(callID: call.id, name: call.name, payload: output,
                               sourceRef: "automation:\(request.method):\(parameterRevision)", sourceRevision: revision,
                               retrievedAt: Date(), evidenceType: evidenceType)
    }

    static func request(for call: AgentToolCall, cloudOnly: Bool = false) throws -> AutomationRequest {
        if cloudOnly { return try cloudRequest(for: call) }
        switch call.name {
        case .profileContext:
            let hasSelector = ["profile", "profileID", "id"].contains { key in
                guard let value = call.arguments[key] else { return false }
                return value != .null
            }
            return AutomationRequest(method: hasSelector ? "profiles.show" : "profiles.list",
                                     params: .object(call.arguments))

        case .chartContext:
            return AutomationRequest(method: "chart.show", params: .object(call.arguments))

        case .dayContext:
            return AutomationRequest(method: "context.day", params: .object(call.arguments))

        case .eventsContext:
            return AutomationRequest(method: "events.list", params: eventParameters(call.arguments))

        case .notesContext:
            var params = call.arguments
            let kind = (params.removeValue(forKey: "kind") ?? params.removeValue(forKey: "type"))?.stringValue?.lowercased()
            let isInsight = kind == "insight" || kind == "insights"
            let method = params["id"] == nil
                ? (isInsight ? "insights.list" : "journal.list")
                : (isInsight ? "insights.show" : "journal.show")
            return AutomationRequest(method: method, params: .object(params))

        case .knowledgeSearch:
            return AutomationRequest(method: "knowledge.search", params: .object(call.arguments))

        case .knowledgeRead:
            return AutomationRequest(method: "knowledge.read", params: .object(call.arguments))

        case .conversationContext:
            // Conversation history belongs to the caller's frozen prompt
            // context; AppAutomationRouter intentionally has no persistence
            // route for it. Failing closed is safer than returning unrelated
            // application status as if it were conversation evidence.
            throw AgentToolError(name: call.name, message: "conversation_context 需要由会话上下文提供。")
        }
    }

    private static func cloudRequest(for call: AgentToolCall) throws -> AutomationRequest {
        guard allowedTools(cloudOnly: true).contains(call.name) else {
            throw AgentToolError(name: call.name, message: "此工具未向远程 AI 开放。")
        }
        guard let date = call.arguments["date"]?.stringValue,
              date.utf8.count == 10,
              date.utf8.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 ? byte == 45 : (48...57).contains(byte)
              }), let next = nextCivilDate(after: date) else {
            throw AgentToolError(name: call.name, message: "date 需要 1901–2099 年内有效的 YYYY-MM-DD 日期。")
        }
        if call.name == .eventsContext {
            // The cloud tool can read one day only. Model-supplied ranges,
            // profile selectors and all other extra arguments are discarded.
            return AutomationRequest(method: "events.list", params: .object([
                "from": .string(date), "to": .string(next)
            ]))
        }
        let at: String
        if let value = call.arguments["at"] {
            guard let time = value.stringValue, validTime(time) else {
                throw AgentToolError(name: call.name, message: "at 需要 00:00–23:59 的 HH:mm 时间。")
            }
            at = time
        } else { at = "12:00" }
        // calendar.day excludes notes and events, and no profile selector is
        // forwarded, so no personal chart can be calculated on this route.
        return AutomationRequest(method: "calendar.day", params: .object([
            "date": .string(date), "at": .string(at)
        ]))
    }

    private static func validTime(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 5, bytes[2] == 58,
              [0, 1, 3, 4].allSatisfy({ (48...57).contains(bytes[$0]) }),
              let hour = Int(value.prefix(2)), let minute = Int(value.suffix(2)) else { return false }
        return hour < 24 && minute < 60
    }

    private static func cloudProjection(_ value: JSONValue, for name: AgentToolName) throws -> JSONValue {
        guard let object = value.objectValue else {
            throw AgentToolError(name: name, message: "只读工具返回的结构无效。")
        }
        switch name {
        case .dayContext:
            let allowed: Set<String> = ["date", "referenceTime", "timeZone", "flowChart", "almanac", "festivals"]
            return calendarFields(.object(object.filter { allowed.contains($0.key) }))
        case .eventsContext:
            guard let occurrences = object["occurrences"]?.arrayValue else {
                throw AgentToolError(name: name, message: "日程来源缺少事项列表。")
            }
            let rows = try occurrences.map { item -> JSONValue in
                guard let occurrence = item.objectValue,
                      let event = occurrence["record"]?["event"]?.objectValue,
                      let title = event["title"]?.stringValue,
                      let start = occurrence["start"]?.stringValue,
                      let end = occurrence["end"]?.stringValue else {
                    throw AgentToolError(name: name, message: "日程来源包含无效事项。")
                }
                var row: [String: JSONValue] = ["title": .string(title), "start": .string(start), "end": .string(end)]
                for key in ["isAllDay", "isTask", "isCompleted", "taskHasDueDate", "taskDueHasTime"] {
                    if let flag = event[key]?.boolValue { row[key] = .bool(flag) }
                }
                // Avoid calendar titles, account identifiers and raw external
                // metadata. Only the broad origin is needed to interpret it.
                let source: String
                switch event["externalKind"]?.stringValue {
                case nil: source = "local"
                case "appleReminders": source = "appleReminders"
                default: source = "appleCalendar"
                }
                row["source"] = .string(source)
                return .object(row)
            }
            // Router ordering may vary for simultaneous occurrences. Sorting
            // the projected data makes equivalent sets share one revision.
            let sorted = try rows.map { (value: $0, key: try AutomationJSON.encode($0)) }
                .sorted { $0.key.lexicographicallyPrecedes($1.key) }.map(\.value)
            var result: [String: JSONValue] = ["occurrences": .array(sorted)]
            for key in ["from", "toExclusive"] {
                if let date = object[key]?.stringValue { result[key] = .string(date) }
            }
            for key in ["truncated", "appleCalendarAccess", "appleRemindersAccess"] {
                if let flag = object[key]?.boolValue { result[key] = .bool(flag) }
            }
            // Error text may contain local paths or account data. Preserve
            // the incomplete-read signal without disclosing the raw error.
            result["appleReadFailed"] = .bool(object["appleError"]?.stringValue.map { !$0.isEmpty } ?? false)
            return .object(result)
        default:
            throw AgentToolError(name: name, message: "此工具未向远程 AI 开放。")
        }
    }

    /// Calendar DTOs are public computations. Strip private envelopes and
    /// collection timestamps defensively if future Router DTOs nest them.
    private static func calendarFields(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            let excluded: Set<String> = ["snapshotat", "retrievedat", "collectedat", "updatedat",
                                         "profile", "profileid", "profiles", "birthprofile", "birthprofiles",
                                         "private", "events", "notes", "note", "location", "personalreading",
                                         "natalcharts", "strengthbasis", "activecycleindex"]
            return .object(object.filter { !excluded.contains($0.key.lowercased()) }.mapValues(calendarFields))
        case .array(let array): return .array(array.map(calendarFields))
        default: return value
        }
    }

    /// `events_context` accepts a convenient one-day `{date: ...}` selector in
    /// addition to the Router's canonical half-open `{from, to}` range.
    private static func eventParameters(_ arguments: [String: JSONValue]) -> JSONValue {
        guard arguments["date"] != nil, arguments["from"] == nil, arguments["to"] == nil,
              let date = arguments["date"]?.stringValue,
              let next = nextCivilDate(after: date) else { return .object(arguments) }
        var params = arguments
        params.removeValue(forKey: "date")
        params["from"] = .string(date)
        params["to"] = .string(next)
        return .object(params)
    }

    private static func nextCivilDate(after value: String) -> String? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1901...2099).contains(year) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "Asia/Shanghai") else { return nil }
        calendar.timeZone = zone
        let components = DateComponents(year: year, month: month, day: day)
        guard let start = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: start).year == year,
              calendar.dateComponents([.year, .month, .day], from: start).month == month,
              calendar.dateComponents([.year, .month, .day], from: start).day == day,
              let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let output = DateFormatter()
        output.calendar = calendar
        output.locale = Locale(identifier: "en_US_POSIX")
        output.timeZone = zone
        output.dateFormat = "yyyy-MM-dd"
        return output.string(from: next)
    }

    /// Extracts a revision from Router envelopes without treating retrieval
    /// timestamps or generated chart values as a persistent revision.
    private static func revision(in value: JSONValue) -> String? {
        guard let object = value.objectValue else { return nil }
        if let revision = object["revision"]?.stringValue { return revision }
        if let profile = object["profile"], let revision = revision(in: profile) { return revision }
        if let note = object["note"], let revision = revision(in: note) { return revision }
        if let event = object["event"], let revision = revision(in: event) { return revision }
        if let record = object["record"], let revision = revision(in: record) { return revision }
        for key in ["occurrences", "notes", "profiles", "items"] {
            if let values = object[key]?.arrayValue, let revision = collectionRevision(values) { return revision }
        }
        return nil
    }

    private static func collectionRevision(_ values: [JSONValue]) -> String? {
        let revisions = values.compactMap { revision(in: $0) }.sorted()
        guard !revisions.isEmpty else { return nil }
        let snapshot = JSONValue.array(revisions.map { JSONValue.string($0) })
        return try? AutomationSnapshot.revision(snapshot)
    }
}
