import Foundation
import LingxiCore

/// Compiles the actual App store; every file and defaults suite here is synthetic.
/// This executable never initializes AppStore, EventKit, notifications, or a GUI.
@main struct BirthProfileStoreChecks {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lingxi-profile-store-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suiteName = "lingxi.profile.checks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let file = folder.appendingPathComponent("profiles.json")
        let repository = BirthProfileRepository(fileURL: file)
        var checks = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
            guard try condition() else { throw Failure.assertion(label) }
            checks += 1
            print("PASS " + label)
        }
        let original = BirthProfile(name: "合成旧档案", birthYear: 1990, birthMonth: 6, birthDay: 15)
        try repository.save([original])
        let store = BirthProfileStore(fileURL: file, defaults: defaults)
        let active = store.activeID
        var external = original
        external.name = "合成外部新名称"
        external.birthMinute = 31
        let additional = BirthProfile(name: "合成外部新增档案", birthYear: 2000, birthMonth: 2, birthDay: 5)
        try repository.save([external, additional])
        let externalBytes = try Data(contentsOf: file)
        var staleToggle = original
        staleToggle.birthdayTracking = .lunar
        try check(!store.save(staleToggle), "stale birthday update is rejected after an external profile edit")
        try check(try Data(contentsOf: file) == externalBytes, "rejected save preserves every external record byte-for-byte")
        try check(store.profiles == [original] && store.activeID == active, "rejected save publishes no changed profile or active selection")
        try check(store.error?.contains("磁盘") == true, "stale snapshot has a readable recovery message")
        try check(!store.delete(original), "stale delete is rejected after an external edit")
        try check(try Data(contentsOf: file) == externalBytes, "rejected delete preserves the newer disk contents")
        try check(store.profiles == [original] && store.activeID == active, "rejected delete changes neither in-memory records nor selection")

        let refreshed = BirthProfileStore(fileURL: file, defaults: defaults)
        var current = external
        current.birthdayTracking = .solar
        try check(refreshed.save(current), "normal save succeeds after reloading the actual disk snapshot")
        try check(try repository.load() == [current, additional], "normal update preserves the unrelated externally added profile")
        try check(refreshed.error == nil, "successful save clears the old error")
        try check(refreshed.delete(current), "normal deletion succeeds")
        try check(try repository.load() == [additional], "normal delete removes only its target")
        try check(refreshed.activeID == additional.id, "normal delete selects a surviving profile")
        try check(refreshed.delete(current), "repeated deletion of an already missing unchanged record is harmless")
        let fresh = BirthProfile(name: "合成新增", birthYear: 2001, birthMonth: 3, birthDay: 1)
        try check(refreshed.save(fresh), "normal creation succeeds")
        try check(try repository.load() == [additional, fresh], "normal creation retains other records")

        // A file that became corrupt after the store was opened must not be
        // silently recovered by replacing it with the stale valid collection.
        let corrupt = Data("{broken-profile-file".utf8)
        try corrupt.write(to: file)
        try check(!refreshed.save(fresh), "late corruption blocks save")
        try check(!refreshed.delete(fresh), "late corruption blocks delete")
        try check(try Data(contentsOf: file) == corrupt, "corrupt original is retained untouched")
        print("BirthProfileStore checks passed: \(checks); temporary synthetic files removed on exit.")
    }
    private enum Failure: Error { case assertion(String) }
}
