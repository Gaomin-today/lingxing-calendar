import Foundation
import Combine
import LingxiCore

@MainActor final class BirthProfileStore: ObservableObject {
    static let maximumNameLength = 40
    private static let activeDefaultsKey = "activeBirthProfileID"

    @Published private(set) var profiles: [BirthProfile] = []
    @Published var activeID: UUID? {
        didSet {
            if let id = activeID, !profiles.contains(where: { $0.id == id }) {
                activeID = oldValue.flatMap { previous in profiles.contains(where: { $0.id == previous }) ? previous : nil }
                return
            }
            persistSelection()
        }
    }
    @Published private(set) var error: String?
    @Published private(set) var isReadOnly = false

    let repository: BirthProfileRepository
    private let defaults: UserDefaults

    var activeProfile: BirthProfile? { profiles.first { $0.id == activeID } }
    var fileURL: URL { repository.fileURL }

    init(fileURL: URL, defaults: UserDefaults = .standard) {
        repository = BirthProfileRepository(fileURL: fileURL)
        self.defaults = defaults
        do {
            profiles = try repository.load()
            let savedID = defaults.string(forKey: Self.activeDefaultsKey).flatMap(UUID.init(uuidString:))
            activeID = savedID.flatMap { id in profiles.contains(where: { $0.id == id }) ? id : nil } ?? profiles.first?.id
            persistSelection()
        } catch {
            // Do not replace the file or erase a previously saved selection when
            // loading fails. A repaired file can be read on the next launch.
            isReadOnly = true
            self.error = "出生档案读取失败，原文件已保留，暂不可保存或删除。\n\(error.localizedDescription)\n文件：\(fileURL.path)"
        }
    }

    @discardableResult func save(_ profile: BirthProfile) -> Bool {
        guard !isReadOnly else { return false }
        var cleaned = profile
        cleaned.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.timeZoneIdentifier = profile.timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.birthplace = profile.birthplace.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = Self.nameError(for: cleaned.name) { error = problem; return false }
        do {
            try cleaned.validate()
            var updated = profiles
            if let index = updated.firstIndex(where: { $0.id == cleaned.id }) { updated[index] = cleaned }
            else { updated.append(cleaned) }
            try repository.save(updated)
            profiles = updated
            activeID = cleaned.id
            error = nil
            return true
        } catch {
            self.error = "档案未保存，已有资料保持不变。\n\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult func delete(_ profile: BirthProfile) -> Bool {
        guard !isReadOnly else { return false }
        guard profiles.contains(where: { $0.id == profile.id }) else { return true }
        let updated = profiles.filter { $0.id != profile.id }
        do {
            try repository.save(updated)
            let nextSelection = activeID == profile.id ? updated.first?.id : activeID
            profiles = updated
            activeID = nextSelection
            error = nil
            return true
        } catch {
            self.error = "档案未删除，已有资料保持不变。\n\(error.localizedDescription)"
            return false
        }
    }

    static func nameError(for name: String) -> String? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "请填写姓名或称呼。" }
        if cleaned.count > maximumNameLength { return "姓名或称呼最多 \(maximumNameLength) 个字。" }
        if cleaned.rangeOfCharacter(from: .newlines) != nil { return "姓名或称呼请写在同一行。" }
        return nil
    }

    private func persistSelection() {
        if let activeID { defaults.set(activeID.uuidString, forKey: Self.activeDefaultsKey) }
        else { defaults.removeObject(forKey: Self.activeDefaultsKey) }
    }
}
