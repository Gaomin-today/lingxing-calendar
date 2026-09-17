import Foundation

/// Versioned values shared by the local CLI and the application. No model SDK is required.
public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public var objectValue: [String: JSONValue]? { if case .object(let value) = self { return value }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let value) = self { return value }; return nil }
    public var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    public var intValue: Int? {
        guard case .number(let value) = self, value.isFinite, value.rounded() == value,
              value >= Double(Int.min), value < Double(Int.max) else { return nil }
        return Int(value)
    }
    public var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    public subscript(key: String) -> JSONValue? { objectValue?[key] }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public static func from<T: Encodable>(_ value: T) throws -> JSONValue {
        try AutomationJSON.decode(JSONValue.self, from: AutomationJSON.encode(value))
    }
}

public enum AutomationJSON {
    /// Stable key ordering for request fingerprints and the public JSON protocol.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard validTimestamp(value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date must be a complete, valid RFC 3339 timestamp with a timezone.")
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date must be an ISO 8601 timestamp with a timezone.")
        }
        return try decoder.decode(type, from: data)
    }

    /// ISO8601DateFormatter alone normalizes February 30 and accepts trailing text.
    /// Validate civil components before parsing so an Agent cannot silently create the wrong date.
    private static func validTimestamp(_ value: String) -> Bool {
        let pattern = #"\A([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]{1,9})?(Z|[+-]([0-9]{2}):([0-9]{2}))\z"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return false }
        func component(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return Int(value[range])
        }
        guard let year = component(1), year > 0, let month = component(2), (1...12).contains(month),
              let day = component(3), (1...31).contains(day),
              let hour = component(4), (0...23).contains(hour),
              let minute = component(5), (0...59).contains(minute),
              let second = component(6), (0...59).contains(second) else { return false }
        if let offsetHour = component(8) {
            guard offsetHour <= 23, let offsetMinute = component(9), offsetMinute <= 59 else { return false }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return components.year == year && components.month == month && components.day == day
    }
}

public struct AutomationRequest: Codable, Equatable, Sendable {
    public var version: Int
    public var requestID: String?
    public var method: String
    public var params: JSONValue
    enum CodingKeys: String, CodingKey { case version, requestID = "request_id", method, params }
    public init(version: Int = 1, requestID: String? = nil, method: String, params: JSONValue = .object([:])) {
        self.version = version; self.requestID = requestID; self.method = method; self.params = params
    }
}

public struct AutomationFailure: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var details: JSONValue?
    public init(code: String, message: String, details: JSONValue? = nil) {
        self.code = code; self.message = message; self.details = details
    }
}

public struct AutomationResponse: Codable, Equatable, Sendable {
    public var version: Int
    public var requestID: String?
    public var ok: Bool
    public var result: JSONValue?
    public var error: AutomationFailure?
    public var replayed: Bool
    enum CodingKeys: String, CodingKey { case version, requestID = "request_id", ok, result, error, replayed }
    public init(version: Int = 1, requestID: String? = nil, ok: Bool, result: JSONValue? = nil,
                error: AutomationFailure? = nil, replayed: Bool = false) {
        self.version = version; self.requestID = requestID; self.ok = ok; self.result = result
        self.error = error; self.replayed = replayed
    }
    public static func success(request: AutomationRequest, result: JSONValue, replayed: Bool = false) -> Self {
        Self(requestID: request.requestID, ok: true, result: result, replayed: replayed)
    }
    public static func failure(request: AutomationRequest? = nil, code: String, message: String, details: JSONValue? = nil) -> Self {
        Self(requestID: request?.requestID, ok: false, error: AutomationFailure(code: code, message: message, details: details))
    }
}
