import Foundation
import Combine
import LingxiCore

@MainActor final class MilestoneStore: ObservableObject {
    @Published private(set) var milestones: [Milestone] = []
    @Published private(set) var error: String?
    @Published private(set) var isReadOnly = false
    let repository: MilestoneRepository

    /// The caller chooses a preview-specific file next to preview events; this
    /// store never derives a real-user fallback when the preview file is absent.
    init(fileURL: URL) {
        repository = MilestoneRepository(fileURL: fileURL)
        do { milestones = try repository.load() }
        catch { self.error = "倒计时读取失败，原文件已保留：\(error.localizedDescription)"; isReadOnly = true }
    }

    @discardableResult func save(_ value: Milestone, replacing original: Milestone?) -> Bool {
        guard !isReadOnly else { return false }
        let current = milestones.first { $0.id == value.id }
        guard current == original else {
            error = "这条记录已在别处修改或删除，请重新打开后编辑。"; return false
        }
        var cleaned = value
        cleaned.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.note = value.note.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = milestones
        if let index = updated.firstIndex(where: { $0.id == cleaned.id }) { updated[index] = cleaned }
        else { updated.append(cleaned) }
        return persist(updated)
    }
    @discardableResult func delete(_ original: Milestone) -> Bool {
        guard !isReadOnly else { return false }
        guard milestones.first(where: { $0.id == original.id }) == original else {
            error = "这条记录已在别处修改或删除，未执行删除。"; return false
        }
        return persist(milestones.filter { $0.id != original.id })
    }
    private func persist(_ values: [Milestone]) -> Bool {
        do {
            guard try repository.load() == milestones else {
                error = "磁盘上的倒计时已被修改，请重启应用核对后再保存。"; return false
            }
            try repository.save(values)
            milestones = values; error = nil; return true
        } catch { self.error = "倒计时未保存，原文件已保留：\(error.localizedDescription)"; return false }
    }
}
