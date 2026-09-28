import Foundation
import Combine
import LingxiCore

@MainActor final class DayNoteStore: ObservableObject {
    @Published private(set) var notes: [DayNote] = []
    @Published private(set) var error: String?
    @Published private(set) var isReadOnly = false
    let repository: DayNoteRepository

    init(fileURL: URL) {
        repository = DayNoteRepository(fileURL: fileURL)
        do { notes = try repository.load() }
        catch { self.error = "日笺读取失败，原文件已保留：\(error.localizedDescription)"; isReadOnly = true }
    }
    @discardableResult func save(_ note: DayNote) -> Bool {
        guard !isReadOnly else { return false }
        var updated = notes
        if let index = updated.firstIndex(where: { $0.id == note.id }) { updated[index] = note }
        else { updated.append(note) }
        return persist(updated)
    }
    @discardableResult func delete(_ note: DayNote) -> Bool {
        guard !isReadOnly else { return false }
        return persist(notes.filter { $0.id != note.id })
    }
    private func persist(_ updated: [DayNote]) -> Bool {
        do { try repository.save(updated); notes = updated; error = nil; return true }
        catch { self.error = "日笺未保存：\(error.localizedDescription)"; return false }
    }
    func entries(on date: String, profileID: UUID?) -> [DayNote] {
        notes.filter { $0.date == date && ($0.profileID == nil || $0.profileID == profileID) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    func isStale(_ note: DayNote, profiles: [BirthProfile]) -> Bool {
        guard let id = note.profileID else { return false }
        guard let profile = profiles.first(where: { $0.id == id }) else { return true }
        guard let revision = note.profileRevision else { return note.kind == .insight }
        return !matchesProfileRevision(revision, profile: profile)
    }
    func latestAssessment(for profile: BirthProfile) -> DayNote? {
        return notes.filter { note in
            note.kind == .insight && note.profileID == profile.id && note.strengthAssessment != nil
                && note.profileRevision.map { matchesProfileRevision($0, profile: profile) } == true
        }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func matchesProfileRevision(_ revision: String, profile: BirthProfile) -> Bool {
        // New analysis ignores presentation/reminder changes. Earlier Agent
        // notes used a full profile revision; accept those only while that
        // exact profile still matches, without rewriting an old receipt.
        (try? profile.analysisRevision()) == revision || (try? AutomationSnapshot.revision(profile)) == revision
    }
}
