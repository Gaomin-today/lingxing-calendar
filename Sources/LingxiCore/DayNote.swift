import Foundation

public enum DayNoteKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case journal, insight
    public var id: String { rawValue }
    public var label: String { self == .journal ? "日记" : "分析与建议" }
}

public enum DayNoteSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case user, agent
    public var id: String { rawValue }
    public var label: String { self == .user ? "自己记录" : "Agent 写入" }
}

public enum DayNoteError: Error, LocalizedError, Equatable, Sendable {
    case invalidDate, invalidTitle, invalidBody, invalidAuthor, invalidTimestamps
    case invalidProfileRevision, invalidStrengthAssessment, duplicateIdentifiers

    public var errorDescription: String? {
        switch self {
        case .invalidDate: return "日笺日期须为 1901–2099 年内真实的公历日期，格式为 YYYY-MM-DD。"
        case .invalidTitle: return "日笺标题需为 1–120 个字符，不能只有空白。"
        case .invalidBody: return "日笺正文需为 1–100000 个字符，不能只有空白。"
        case .invalidAuthor: return "作者名称需为 1–120 个字符，不能只有空白。"
        case .invalidTimestamps: return "日笺创建与更新时间无效，更新时间不能早于创建时间。"
        case .invalidProfileRevision: return "档案版本必须关联一个档案，且版本标识不能为空或超过 256 个字符。"
        case .invalidStrengthAssessment: return "旺衰结论须由 Agent 写入分析，并关联所依据的档案及版本。"
        case .duplicateIdentifiers: return "日笺包含重复标识，已保留原文件，请先修复数据。"
        }
    }
}

/// A calendar civil day, not an instant inferred from the birth location or the
/// computer's current time zone. Analysis text retains its author and source;
/// it is never substituted for the deterministic chart calculation itself.
public struct DayNote: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: DayNoteKind
    public var date: String
    public var profileID: UUID?
    public var title: String
    public var body: String
    public var source: DayNoteSource
    public var author: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var profileRevision: String?
    public var strengthAssessment: BaziStrengthAssumption?

    public static let calendarTimeZoneIdentifier = "Asia/Shanghai"

    public init(
        id: UUID = UUID(), kind: DayNoteKind = .journal, date: String,
        profileID: UUID? = nil, title: String, body: String,
        source: DayNoteSource = .user, author: String? = nil,
        createdAt: Date = Date(), updatedAt: Date? = nil,
        profileRevision: String? = nil, strengthAssessment: BaziStrengthAssumption? = nil
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.profileID = profileID
        self.title = title
        self.body = body
        self.source = source
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.profileRevision = profileRevision
        self.strengthAssessment = strengthAssessment
    }

    public func validate() throws {
        try Self.validateDate(date)
        guard Self.validText(title, maximum: 120) else { throw DayNoteError.invalidTitle }
        guard Self.validText(body, maximum: 100_000) else { throw DayNoteError.invalidBody }
        if let author, !Self.validText(author, maximum: 120) { throw DayNoteError.invalidAuthor }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt >= createdAt else { throw DayNoteError.invalidTimestamps }
        if let profileRevision {
            guard profileID != nil, Self.validText(profileRevision, maximum: 256) else {
                throw DayNoteError.invalidProfileRevision
            }
        }
        if strengthAssessment != nil {
            guard kind == .insight, source == .agent, profileID != nil, profileRevision != nil else {
                throw DayNoteError.invalidStrengthAssessment
            }
        }
    }

    public static func validateDate(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(value.prefix(4)), let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.suffix(2)), (1901...2099).contains(year) else {
            throw DayNoteError.invalidDate
        }
        var calendar = Calendar(identifier: .gregorian)
        // UTC is used only to check the Gregorian day, avoiding Foundation's
        // normalization of a historical local clock transition at midnight.
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let resolved = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            throw DayNoteError.invalidDate
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: resolved)
        guard parts.year == year, parts.month == month, parts.day == day else { throw DayNoteError.invalidDate }
    }

    private static func validText(_ value: String, maximum: Int) -> Bool {
        value.count <= maximum && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The application is the single writer. A malformed existing file is never
/// replaced with an empty archive after a failed load.
public struct DayNoteRepository: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> [DayNote] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let notes = try JSONDecoder().decode([DayNote].self, from: Data(contentsOf: fileURL))
        try Self.validate(notes)
        return notes
    }

    public func save(_ notes: [DayNote]) throws {
        try Self.validate(notes)
        if FileManager.default.fileExists(atPath: fileURL.path) { _ = try load() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(notes)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func defaultURL() -> URL {
        EventRepository.defaultURL().deletingLastPathComponent().appendingPathComponent("notes.json", isDirectory: false)
    }

    private static func validate(_ notes: [DayNote]) throws {
        guard Set(notes.map(\.id)).count == notes.count else { throw DayNoteError.duplicateIdentifiers }
        for note in notes { try note.validate() }
    }
}
