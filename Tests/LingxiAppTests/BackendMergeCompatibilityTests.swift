import Foundation
import Testing
import LingxiAgent
import LingxiCore
@testable import LingxiApp

@MainActor struct BackendMergeCompatibilityTests {
    @Test func oldAgentAnalysisRemainsValidAcrossBirthdayPreferencesButNotBirthDataChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lingxi-note-merge-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DayNoteStore(fileURL: directory.appendingPathComponent("notes.json"))
        var profile = BirthProfile(name: "合成合并档案", birthYear: 1990, birthMonth: 1, birthDay: 1)
        let originalRevision = try AutomationSnapshot.revision(profile)
        let note = DayNote(kind: .insight, date: "2026-09-28", profileID: profile.id,
                           title: "合成分析", body: "仅用于合并回归。", source: .agent,
                           profileRevision: originalRevision, strengthAssessment: .strong)
        #expect(store.save(note))
        #expect(store.isStale(note, profiles: [profile]) == false)
        #expect(store.latestAssessment(for: profile)?.id == note.id)

        profile.birthdayTracking = .solar
        #expect(try AutomationSnapshot.revision(profile) != originalRevision)
        #expect(try profile.analysisRevision() == originalRevision)
        #expect(store.isStale(note, profiles: [profile]) == false)
        #expect(store.latestAssessment(for: profile)?.id == note.id)

        profile.birthDay = 2
        #expect(store.isStale(note, profiles: [profile]))
        #expect(store.latestAssessment(for: profile) == nil)
    }

    @Test func legacyFolderNeedsExplicitEnablementAndPurposeAndRevocationStillWorks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lingxi-knowledge-merge-" + UUID().uuidString)
        let suite = "lingxi-knowledge-merge-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "# 合成知识\n合并回归专用知识标记：仅供测试。".write(to: directory.appendingPathComponent("synthetic.md"), atomically: true, encoding: .utf8)
        defaults.set([directory.path], forKey: "knowledgeFolders")
        let knowledge = KnowledgeLibrary(defaults: defaults)
        let collection = try #require(knowledge.collections.first)
        #expect(collection.isEnabled == false)
        #expect(knowledge.accessError == nil)
        #expect(try knowledge.search(query: "合并回归专用知识标记", purpose: "合并回归核对资料")["privateReturned"]?.intValue == 0)

        knowledge.setEnabled(true, for: collection.id)
        #expect(try knowledge.search(query: "合并回归专用知识标记")["privateReturned"]?.intValue == 0)
        let call = AgentToolCall(name: .knowledgeSearch, arguments: ["query": .string("合并回归专用知识标记"), "purpose": .string("合并回归核对资料")])
        let routed = try AppAutomationToolProvider.request(for: call)
        #expect(routed.method == "knowledge.search")
        #expect(routed.params["purpose"] == .string("合并回归核对资料"))
        #expect(throws: AgentToolError.self) { try AppAutomationToolProvider.request(for: call, cloudOnly: true) }
        let results = try knowledge.search(query: "合并回归专用知识标记", purpose: "合并回归核对资料")
        let item = try #require(results["items"]?.arrayValue?.first { $0["access"]?.stringValue == "private_excerpt" })
        let id = try #require(item["id"]?.stringValue)
        #expect(throws: KnowledgeAccessError.self) { try knowledge.read(id: id, offset: 0) }
        let excerpt = try knowledge.read(id: id, offset: 0, purpose: "合并回归核对资料")
        #expect(excerpt["content"]?.stringValue?.contains("合并回归专用知识标记") == true)
        #expect(excerpt["sourcePath"] == nil)
        #expect(knowledge.remaining(for: collection) < collection.dailyCharacterLimit)
        #expect(knowledge.audit.contains { $0.action == "read" })

        knowledge.setEnabled(false, for: collection.id)
        #expect(throws: KnowledgeAccessError.self) { try knowledge.read(id: id, offset: 0, purpose: "合并回归核对资料") }
        let reloaded = KnowledgeLibrary(defaults: defaults)
        #expect(reloaded.accessError == nil)
        #expect(reloaded.collections.first?.isEnabled == false)
        #expect(reloaded.remaining(for: collection) < collection.dailyCharacterLimit)
    }
}
