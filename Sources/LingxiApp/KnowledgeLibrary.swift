import Foundation
import Combine
import LingxiCore

@MainActor final class KnowledgeLibrary: ObservableObject {
    static let shared = KnowledgeLibrary()
    @Published private(set) var collections: [KnowledgeCollection]
    @Published private(set) var audit: [KnowledgeAccessAudit]
    @Published private(set) var accessError: String?
    private let defaults: UserDefaults
    private var access: ControlledKnowledgeAccess
    private let collectionKey = "knowledgeCollections.v2"
    private let accessKey = "knowledgeAccessState.v1"
    private var builtinRoot: URL? { Bundle.main.resourceURL?.appendingPathComponent("Knowledge") }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let collectionKey = "knowledgeCollections.v2", accessKey = "knowledgeAccessState.v1"
        let loadedCollections: [KnowledgeCollection]
        var damaged = false
        if defaults.object(forKey: collectionKey) != nil {
            if let data = defaults.data(forKey: collectionKey), let saved = try? JSONDecoder().decode([KnowledgeCollection].self, from: data),
               Set(saved.map(\.id)).count == saved.count, Set(saved.map(\.directoryPath)).count == saved.count {
                loadedCollections = saved
            } else { loadedCollections = []; damaged = true }
        } else {
            // Old registrations remain available in settings, but access must be enabled again.
            loadedCollections = (defaults.stringArray(forKey: "knowledgeFolders") ?? []).enumerated().map { index, path in
                KnowledgeCollection(name: "私有资料 \(index + 1)", directoryPath: path)
            }
            if let data = try? JSONEncoder().encode(loadedCollections) { defaults.set(data, forKey: collectionKey) }
        }
        var state = KnowledgeAccessState()
        if defaults.object(forKey: accessKey) != nil {
            if let data = defaults.data(forKey: accessKey), let saved = try? JSONDecoder().decode(KnowledgeAccessState.self, from: data) { state = saved }
            else { damaged = true }
        } else if loadedCollections.contains(where: \.isEnabled) { damaged = true }
        collections = loadedCollections
        access = ControlledKnowledgeAccess(state: state)
        audit = state.audit
        accessError = damaged ? "集合授权或访问记录无法读取，私有查询已暂停，原记录仍保留。内置公开说明不受影响。" : nil
        if !damaged, defaults.object(forKey: accessKey) == nil, let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: accessKey) }
    }
    func register(_ url: URL) throws {
        if let accessError { throw KnowledgeAccessError("knowledge_storage_unavailable", accessError) }
        let root = url.resolvingSymlinksInPath().standardizedFileURL
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else {
            throw KnowledgeAccessError("invalid_folder", "请选择可读取的资料文件夹。")
        }
        guard !collections.contains(where: { $0.directoryPath == root.path }) else { return }
        collections.append(KnowledgeCollection(name: "私有资料 \(collections.count + 1)", directoryPath: root.path))
        saveCollections()
    }
    func remove(_ id: UUID) {
        guard accessError == nil else { return }
        access.revoke(collectionID: id)
        collections.removeAll { $0.id == id }; saveCollections()
    }
    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard accessError == nil else { return }
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].isEnabled = enabled
        if !enabled { access.revoke(collectionID: id) }
        saveCollections()
    }
    func setLimit(_ limit: Int, for id: UUID) {
        guard accessError == nil else { return }
        guard KnowledgeCollection.allowedLimits.contains(limit), let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].dailyCharacterLimit = limit; saveCollections()
    }
    func resetBudget(for id: UUID) { guard accessError == nil else { return }; access.resetBudget(collectionID: id); saveAccess() }
    func recoverAccess() {
        for key in [collectionKey, accessKey] {
            if let original = defaults.object(forKey: key) { defaults.set(original, forKey: key + ".recoveryBackup") }
        }
        collections = collections.map { value in var value = value; value.isEnabled = false; return value }
        access = ControlledKnowledgeAccess(); accessError = nil
        saveCollections(); saveAccess()
    }
    func remaining(for collection: KnowledgeCollection) -> Int {
        max(0, collection.dailyCharacterLimit - access.usedCharacters(collectionID: collection.id))
    }
    func collectionName(_ id: UUID) -> String { collections.first { $0.id == id }?.name ?? "已移除集合" }
    func search(query: String, purpose: String? = nil) throws -> JSONValue {
        verifyPersistedAccess()
        if let accessError {
            var result = try access.search(query: query, collections: [], builtinRoot: builtinRoot).objectValue ?? [:]
            result["privateNotice"] = .string(accessError)
            result["privateAccessError"] = .string("knowledge_storage_unavailable")
            return .object(result)
        }
        defer { saveAccess() }
        return try access.search(query: query, purpose: purpose, collections: collections, builtinRoot: builtinRoot)
    }
    func read(id: String, offset: Int, purpose: String? = nil) throws -> JSONValue {
        verifyPersistedAccess()
        if id.hasPrefix("excerpt-"), let accessError { throw KnowledgeAccessError("knowledge_storage_unavailable", accessError) }
        defer { saveAccess() }
        return try access.read(id: id, offset: offset, purpose: purpose, collections: collections, builtinRoot: builtinRoot)
    }
    private func saveCollections() {
        guard accessError == nil else { return }
        if let data = try? JSONEncoder().encode(collections) { defaults.set(data, forKey: collectionKey) }
    }
    private func verifyPersistedAccess() {
        guard accessError == nil else { return }
        guard let stateData = defaults.data(forKey: accessKey), let savedState = try? JSONDecoder().decode(KnowledgeAccessState.self, from: stateData),
              savedState == access.state,
              let collectionData = defaults.data(forKey: collectionKey), let savedCollections = try? JSONDecoder().decode([KnowledgeCollection].self, from: collectionData),
              savedCollections == collections else {
            accessError = "集合授权或额度记录在应用外发生变化或无法读取，私有查询已暂停，原记录仍保留。"
            return
        }
    }
    private func saveAccess() {
        guard accessError == nil else { return }
        if let data = try? JSONEncoder().encode(access.state) { defaults.set(data, forKey: accessKey) }
        audit = access.state.audit
    }
}
