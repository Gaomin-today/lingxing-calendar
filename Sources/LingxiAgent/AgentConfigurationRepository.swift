import CryptoKit
import Darwin
import Foundation

/// The four user-facing configuration documents.  The filename is also the
/// stable wire representation used on disk and by the settings UI.
public enum AgentConfigDocument: String, CaseIterable, Identifiable, Codable, Sendable {
    case soul = "SOUL.md"
    case agent = "AGENT.md"
    case user = "USER.md"
    case skill = "SKILL.md"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .soul: return "阿灵的气质"
        case .agent: return "工作习惯"
        case .user: return "我的偏好"
        case .skill: return "聊天 Skill"
        }
    }

    public var help: String {
        switch self {
        case .soul: return "称呼、语气和陪伴方式。不能改变事实优先和安全边界。"
        case .agent: return "读取顺序、复核习惯和回答结构。不能扩大工具权限。"
        case .user: return "你希望阿灵知道的称呼、语言和表达偏好。"
        case .skill: return "聊天任务的工作方法。正文中的命令不会获得额外权限。"
        }
    }

    public var defaultContent: String {
        switch self {
        case .soul:
            return """
            # 阿灵

            温和、清楚、尊重用户的选择。用日常语言解释传统文化，不故弄玄虚，不把民俗说法包装成确定预测。
            """
        case .agent:
            return """
            # 工作习惯

            先读取应用提供的确定性事实，再读取必要资料，最后复核来源。回答区分应用事实、传统解释、行动建议和不确定性。遇到冲突时保留分支，不静默选择。
            """
        case .user:
            return ""
        case .skill:
            return """
            # 聊天解读

            围绕用户的问题读取最小必要资料。不要编造缺失的出生时刻、日程或知识来源；用户明确要求保存时，只生成本地确认卡，等待确认后再写入。
            """
        }
    }
}

public struct AgentConfigSnapshot: Codable, Equatable, Sendable {
    public let document: AgentConfigDocument
    public let content: String
    public let revision: String
    public let isDefault: Bool

    public init(document: AgentConfigDocument, content: String, revision: String, isDefault: Bool) {
        self.document = document
        self.content = content
        self.revision = revision
        self.isDefault = isDefault
    }
}

public struct AgentConfigHistory: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let document: AgentConfigDocument
    public let date: Date
    public let content: String
    public let revision: String
    public let isDefault: Bool

    public init(id: String, document: AgentConfigDocument, date: Date, content: String,
                revision: String, isDefault: Bool) {
        self.id = id
        self.document = document
        self.date = date
        self.content = content
        self.revision = revision
        self.isDefault = isDefault
    }
}

public enum AgentConfigurationRepositoryError: Error, LocalizedError, Equatable, Sendable {
    case invalidContent
    case contentTooLarge
    case invalidRevision
    case revisionConflict(expected: String, actual: String)
    case historyNotFound
    case invalidHistory
    case historyTooLarge
    case writeVerificationFailed
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidContent: return "配置正文无效。"
        case .contentTooLarge: return "配置过长，请缩短正文（最多 8000 字符或 32000 字节）。"
        case .invalidRevision: return "配置版本标识无效。"
        case .revisionConflict: return "配置已被其他操作修改，请重新加载后再保存。"
        case .historyNotFound: return "历史配置版本不存在或已被移除。"
        case .invalidHistory: return "历史配置版本已损坏，未恢复任何内容。"
        case .historyTooLarge: return "历史配置版本过多，未加载。"
        case .writeVerificationFailed: return "保存后校验失败，已保留上一版备份。"
        case let .ioFailure(message): return "配置文件操作失败：\(message)"
        }
    }
}

/// Bounded, revision-checked storage for the four local Markdown documents.
/// Root files remain human-readable; history entries are self-contained JSON
/// records so the content, revision and timestamp cannot drift apart.
public struct AgentConfigurationRepository: Sendable {
    public static let maximumCharacters = 8_000

    private static let maximumBytes = maximumCharacters * 4
    private static let maximumHistoryBytes = maximumBytes * 2 + 8_192
    private static let maximumHistoryFiles = 1_024
    private static let historyDirectoryName = "history"

    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func load(_ document: AgentConfigDocument) throws -> AgentConfigSnapshot {
        try checkDirectoryIfPresent(directoryURL)
        let url = rootURL(for: document)
        guard try fileKind(at: url) != nil else {
            return snapshot(document: document, content: document.defaultContent)
        }
        let content = try readText(at: url)
        try Self.validate(document, content: content)
        return snapshot(document: document, content: content)
    }

    public func save(_ document: AgentConfigDocument, content: String,
                     expectedRevision: String) throws -> AgentConfigSnapshot {
        try Self.validate(document, content: content)
        try Self.validateRevision(expectedRevision)

        // Reading first both checks the caller's optimistic-lock token and
        // detects a corrupt file without replacing it with a default.
        let current = try load(document)
        guard current.revision == expectedRevision else {
            throw AgentConfigurationRepositoryError.revisionConflict(expected: expectedRevision,
                                                                      actual: current.revision)
        }
        if current.content == content { return current }

        let archive = AgentConfigHistory(id: UUID().uuidString, document: document, date: Date(),
                                         content: current.content, revision: current.revision,
                                         isDefault: current.isDefault)
        let archiveURL = try uniqueHistoryURL(for: archive.id)
        do {
            try writeHistory(archive, to: archiveURL)
            try createDirectoryIfNeeded()
            try Data(content.utf8).write(to: rootURL(for: document), options: .atomic)

            // Do not report success until the bytes on disk round-trip and
            // still describe the revision returned to the caller.
            let written = try load(document)
            guard written.content == content, written.revision == revision(of: content) else {
                throw AgentConfigurationRepositoryError.writeVerificationFailed
            }
            return written
        } catch {
            // The root may already contain new bytes when verification fails.
            // Retain the archive: it can be the only copy of the previous value.
            if let repositoryError = error as? AgentConfigurationRepositoryError { throw repositoryError }
            throw AgentConfigurationRepositoryError.ioFailure(error.localizedDescription)
        }
    }

    public func history(for document: AgentConfigDocument) throws -> [AgentConfigHistory] {
        try checkDirectoryIfPresent(directoryURL)
        let folder = directoryURL.appendingPathComponent(Self.historyDirectoryName, isDirectory: true)
        guard try fileKind(at: folder) != nil else { return [] }
        try checkDirectoryIfPresent(folder)
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        } catch {
            throw AgentConfigurationRepositoryError.ioFailure(error.localizedDescription)
        }
        let relevant = urls.filter { isHistoryFile($0, document: document) }
        guard relevant.count <= Self.maximumHistoryFiles else {
            throw AgentConfigurationRepositoryError.historyTooLarge
        }
        var values: [AgentConfigHistory] = []
        values.reserveCapacity(relevant.count)
        for url in relevant {
            if url.pathExtension.lowercased() == "json" {
                let history = try readHistoryJSON(at: url, document: nil)
                if history.document == document { values.append(history) }
            } else {
                values.append(try readLegacyHistory(at: url, document: document))
            }
        }
        return values.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id > $1.id
        }
    }

    public func restore(_ item: AgentConfigHistory, expectedRevision: String) throws -> AgentConfigSnapshot {
        // Never trust a caller-provided history value. It must still exist in
        // the repository and match the complete validated record on disk.
        guard try history(for: item.document).contains(where: { $0 == item }) else {
            throw AgentConfigurationRepositoryError.historyNotFound
        }
        return try save(item.document, content: item.content, expectedRevision: expectedRevision)
    }

    public static func validate(_ document: AgentConfigDocument, content: String) throws {
        guard content.count <= maximumCharacters, content.utf8.count <= maximumBytes else {
            throw AgentConfigurationRepositoryError.contentTooLarge
        }
        if document != .user && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AgentConfigurationRepositoryError.invalidContent
        }
    }

    private func rootURL(for document: AgentConfigDocument) -> URL {
        directoryURL.appendingPathComponent(document.rawValue, isDirectory: false)
    }

    private func createDirectoryIfNeeded() throws {
        try checkDirectoryIfPresent(directoryURL)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw AgentConfigurationRepositoryError.ioFailure(error.localizedDescription)
        }
        try checkDirectoryIfPresent(directoryURL)
    }

    private func snapshot(document: AgentConfigDocument, content: String) -> AgentConfigSnapshot {
        AgentConfigSnapshot(document: document, content: content, revision: revision(of: content),
                            isDefault: content == document.defaultContent)
    }

    private func revision(of content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func validateRevision(_ value: String) throws {
        guard value.utf8.count == 64, value.unicodeScalars.allSatisfy({
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }) else { throw AgentConfigurationRepositoryError.invalidRevision }
    }

    private func readText(at url: URL) throws -> String {
        let data = try readBoundedFile(at: url, maximumBytes: Self.maximumBytes)
        guard let content = String(data: data, encoding: .utf8) else {
            throw AgentConfigurationRepositoryError.invalidContent
        }
        guard content.count <= Self.maximumCharacters else {
            throw AgentConfigurationRepositoryError.contentTooLarge
        }
        return content
    }

    private func uniqueHistoryURL(for id: String) throws -> URL {
        guard Self.validHistoryID(id) else {
            throw AgentConfigurationRepositoryError.invalidHistory
        }
        let folder = directoryURL.appendingPathComponent(Self.historyDirectoryName, isDirectory: true)
        try createDirectoryIfNeeded()
        try checkDirectoryIfPresent(folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw AgentConfigurationRepositoryError.ioFailure(error.localizedDescription)
        }
        try checkDirectoryIfPresent(folder)
        let url = folder.appendingPathComponent(id + ".json", isDirectory: false)
        guard try fileKind(at: url) == nil else {
            // UUID collisions are extraordinarily unlikely; report rather
            // than overwrite an existing trusted version.
            throw AgentConfigurationRepositoryError.ioFailure("历史版本标识冲突。")
        }
        return url
    }

    private struct HistoryRecord: Codable {
        let id: String
        let document: AgentConfigDocument
        let date: Date
        let content: String
        let revision: String
        let isDefault: Bool
    }

    private func writeHistory(_ history: AgentConfigHistory, to url: URL) throws {
        let record = HistoryRecord(id: history.id, document: history.document, date: history.date,
                                   content: history.content, revision: history.revision, isDefault: history.isDefault)
        do {
            let data = try JSONEncoder().encode(record)
            try Data(data).write(to: url, options: .atomic)
            guard try readHistoryJSON(at: url, document: history.document) == history else {
                throw AgentConfigurationRepositoryError.writeVerificationFailed
            }
        } catch let error as AgentConfigurationRepositoryError {
            throw error
        } catch {
            throw AgentConfigurationRepositoryError.ioFailure(error.localizedDescription)
        }
    }

    private func isHistoryFile(_ url: URL, document: AgentConfigDocument) -> Bool {
        let name = url.lastPathComponent
        if url.pathExtension.lowercased() == "json" {
            return name.hasSuffix(".json")
        }
        return name.hasSuffix("-" + document.rawValue)
    }

    private func readHistoryJSON(at url: URL, document: AgentConfigDocument?) throws -> AgentConfigHistory {
        let data = try readBoundedFile(at: url, maximumBytes: Self.maximumHistoryBytes)
        let record: HistoryRecord
        do { record = try JSONDecoder().decode(HistoryRecord.self, from: data) }
        catch { throw AgentConfigurationRepositoryError.invalidHistory }
        guard (document == nil || record.document == document),
              record.id == url.deletingPathExtension().lastPathComponent,
              Self.validHistoryID(record.id),
              record.date.timeIntervalSinceReferenceDate.isFinite,
              record.revision == revision(of: record.content),
              record.isDefault == (record.content == record.document.defaultContent) else {
            throw AgentConfigurationRepositoryError.invalidHistory
        }
        try Self.validate(record.document, content: record.content)
        return AgentConfigHistory(id: record.id, document: record.document, date: record.date,
                                  content: record.content, revision: record.revision, isDefault: record.isDefault)
    }

    private func readLegacyHistory(at url: URL, document: AgentConfigDocument) throws -> AgentConfigHistory {
        let content = try readText(at: url)
        try Self.validate(document, content: content)
        let date: Date
        if let archiveDate = legacyHistoryDate(filename: url.lastPathComponent, document: document) {
            date = archiveDate
        } else {
            do {
                date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
            } catch {
                throw AgentConfigurationRepositoryError.ioFailure(error.localizedDescription)
            }
        }
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw AgentConfigurationRepositoryError.invalidHistory
        }
        return AgentConfigHistory(id: url.lastPathComponent, document: document, date: date,
                                  content: content, revision: revision(of: content),
                                  isDefault: content == document.defaultContent)
    }

    private func legacyHistoryDate(filename: String, document: AgentConfigDocument) -> Date? {
        let suffix = "-" + document.rawValue
        guard filename.hasSuffix(suffix) else { return nil }
        let stamp = String(filename.dropLast(suffix.count))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS'Z'"
        formatter.isLenient = false
        guard let date = formatter.date(from: stamp), formatter.string(from: date) == stamp else { return nil }
        return date
    }

    /// lstat distinguishes a missing path from a dangling link and does not
    /// silently follow a link to a different configuration directory.
    private func fileKind(at url: URL) throws -> mode_t? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            let code = errno
            if code == ENOENT { return nil }
            throw AgentConfigurationRepositoryError.ioFailure(String(cString: strerror(code)))
        }
        return info.st_mode & mode_t(S_IFMT)
    }

    private func checkDirectoryIfPresent(_ url: URL) throws {
        if let kind = try fileKind(at: url), kind != mode_t(S_IFDIR) {
            throw AgentConfigurationRepositoryError.ioFailure("配置目录必须是本机目录，不能是符号链接。")
        }
    }

    private func readBoundedFile(at url: URL, maximumBytes: Int) throws -> Data {
        // O_NONBLOCK prevents a substituted FIFO from blocking open; fstat
        // validates the descriptor itself, and O_NOFOLLOW rejects symlinks.
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw AgentConfigurationRepositoryError.ioFailure("无法读取配置文件；请检查文件类型和访问权限。")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw AgentConfigurationRepositoryError.ioFailure("配置只接受普通文件，不能是目录或符号链接。")
        }
        guard info.st_size <= off_t(maximumBytes) else {
            throw AgentConfigurationRepositoryError.contentTooLarge
        }
        let data: Data
        do { data = try handle.read(upToCount: maximumBytes + 1) ?? Data() }
        catch { throw AgentConfigurationRepositoryError.ioFailure("配置文件读取失败。") }
        guard data.count <= maximumBytes else { throw AgentConfigurationRepositoryError.contentTooLarge }
        return data
    }

    private static func validHistoryID(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= 128 else { return false }
        return id.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (65...90).contains($0.value) ||
            (97...122).contains($0.value) || $0.value == 45 || $0.value == 95
        }
    }
}
