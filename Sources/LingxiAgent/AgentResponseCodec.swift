import Foundation
import LingxiCore

/// Decodes the small JSON envelope requested from a text chat model. Providers
/// that do not honor the envelope still work: the original text becomes the
/// conclusion and no unsupported claims are invented.
public enum AgentResponseCodec {
    public static func decode(_ text: String) -> AgentModelResponse {
        guard let object = jsonObject(in: text) else { return AgentModelResponse(text: text) }
        let rawConclusion = (object["conclusion"] as? String)
            ?? (object["answer"] as? String)
            ?? (object["text"] as? String)
        let conclusion = rawConclusion.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let claims = decodeClaims(object["claims"])
        let toolCalls = decodeToolCalls(object["toolCalls"] ?? object["tool_calls"])
        let critic = decodeCritic(object["critic"])
        let looksStructured = ["conclusion", "answer", "text", "claims", "toolCalls", "tool_calls", "critic", "finished"]
            .contains { object[$0] != nil }
        guard looksStructured else { return AgentModelResponse(text: text) }
        // A tool-only envelope is a request to continue the loop, not prose
        // for the user. Even a mistaken finished:true cannot complete an
        // answer without a conclusion. Combined tool calls and final prose
        // remain supported, as does an explicit unfinished draft.
        let finished = conclusion != nil && ((object["finished"] as? Bool) ?? true)
        return AgentModelResponse(text: conclusion, toolCalls: toolCalls, claims: claims, finished: finished, critic: critic)
    }

    private static func jsonObject(in text: String) -> [String: Any]? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("```") {
            candidate = candidate.replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
            candidate = candidate.replacingOccurrences(of: "```$", with: "", options: .regularExpression)
        }
        guard let start = candidate.firstIndex(of: "{"), let end = candidate.lastIndex(of: "}"), start <= end else { return nil }
        let slice = String(candidate[start...end])
        guard let data = slice.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }

    private static func decodeClaims(_ raw: Any?) -> [AgentClaim] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let text = (row["text"] as? String ?? row["claim"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            let evidenceType = (row["evidenceType"] as? String).flatMap(EvidenceType.init(rawValue:)) ?? .modelInference
            let confidence = min(1, max(0, (row["confidence"] as? NSNumber)?.doubleValue ?? 0.5))
            return AgentClaim(id: row["id"] as? String ?? UUID().uuidString,
                              text: text,
                              sourceRef: row["sourceRef"] as? String ?? row["source"] as? String,
                              sourceRevision: row["sourceRevision"] as? String ?? row["revision"] as? String,
                              evidenceType: evidenceType, confidence: confidence)
        }
    }

    private static func decodeToolCalls(_ raw: Any?) -> [AgentToolCall] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let rawName = row["name"] as? String, let name = AgentToolName(rawValue: rawName) else { return nil }
            let arguments = (row["arguments"] as? [String: Any] ?? [:]).compactMapValues(JSONValue.fromAny)
            return AgentToolCall(id: row["id"] as? String ?? UUID().uuidString, name: name, arguments: arguments)
        }
    }

    private static func decodeCritic(_ raw: Any?) -> AgentCriticReport? {
        guard let row = raw as? [String: Any] else { return nil }
        func strings(_ key: String) -> [String] { row[key] as? [String] ?? [] }
        return AgentCriticReport(passed: row["passed"] as? Bool ?? true,
                                 missingEvidence: strings("missingEvidence"),
                                 conflicts: strings("conflicts"),
                                 staleSources: strings("staleSources"),
                                 unsupportedClaims: strings("unsupportedClaims"),
                                 needsSupplementalRead: row["needsSupplementalRead"] as? Bool ?? false)
    }
}

private extension JSONValue {
    static func fromAny(_ value: Any) -> JSONValue? {
        switch value {
        case _ as NSNull: return .null
        case let value as String: return .string(value)
        case let value as Bool: return .bool(value)
        case let value as NSNumber: return .number(value.doubleValue)
        case let value as [Any]: return .array(value.compactMap(fromAny))
        case let value as [String: Any]: return .object(value.compactMapValues(fromAny))
        default: return nil
        }
    }
}
