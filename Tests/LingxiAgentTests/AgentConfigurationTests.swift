import Foundation
import Testing
@testable import LingxiAgent

struct AgentConfigurationTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lingxi-agent-config-" + UUID().uuidString, isDirectory: true)
    }

    @Test func missingDocumentsExposeDefaultsAndSaveArchivesTheDefault() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let initial = try repository.load(.soul)
        #expect(initial.isDefault)
        #expect(initial.content == AgentConfigDocument.soul.defaultContent)

        let saved = try repository.save(.soul, content: "# 新的阿灵\n\n更安静。", expectedRevision: initial.revision)
        #expect(saved.isDefault == false)
        #expect(try repository.load(.soul).content == saved.content)
        let history = try repository.history(for: .soul)
        #expect(history.count == 1)
        #expect(history.first?.isDefault == true)
        #expect(history.first?.content == AgentConfigDocument.soul.defaultContent)
    }

    @Test func userMayBeEmptyButOtherDocumentsRejectBlankContent() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let user = try repository.load(.user)
        let emptyUser = try repository.save(.user, content: "\n\n", expectedRevision: user.revision)
        #expect(emptyUser.content == "\n\n")
        let soul = try repository.load(.soul)
        #expect(throws: AgentConfigurationRepositoryError.invalidContent) {
            try repository.save(.soul, content: " \n\t", expectedRevision: soul.revision)
        }
        #expect(try repository.load(.soul).content == AgentConfigDocument.soul.defaultContent)
    }

    @Test func historyCanBeRestoredAndConcurrentDiskChangesAreRejected() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let first = try repository.load(.agent)
        let second = try repository.save(.agent, content: "A", expectedRevision: first.revision)
        let third = try repository.save(.agent, content: "B", expectedRevision: second.revision)
        let history = try repository.history(for: .agent)
        #expect(history.count == 2)
        #expect(Set(history.map(\.content)) == Set([first.content, "A"]))

        let path = root.appendingPathComponent(AgentConfigDocument.agent.rawValue)
        try Data("external".utf8).write(to: path, options: .atomic)
        #expect(throws: AgentConfigurationRepositoryError.self) {
            try repository.save(.agent, content: "C", expectedRevision: third.revision)
        }
        #expect(try String(contentsOf: path, encoding: .utf8) == "external")
    }

    @Test func corruptedRootIsNotSilentlyReplaced() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent(AgentConfigDocument.skill.rawValue)
        let original = Data([0xff, 0xfe, 0xfd])
        try original.write(to: path)
        let repository = AgentConfigurationRepository(directoryURL: root)
        #expect(throws: AgentConfigurationRepositoryError.self) { try repository.load(.skill) }
        #expect(try Data(contentsOf: path) == original)
    }

    @Test func historyIsFilteredByDocumentAndRestoreCreatesANewVersion() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let soul = try repository.load(.soul)
        _ = try repository.save(.soul, content: "A", expectedRevision: soul.revision)
        let agent = try repository.load(.agent)
        _ = try repository.save(.agent, content: "B", expectedRevision: agent.revision)
        let soulHistory = try repository.history(for: .soul)
        #expect(soulHistory.allSatisfy { $0.document == .soul })
        let restored = try repository.restore(soulHistory[0], expectedRevision: try repository.load(.soul).revision)
        #expect(restored.content == soulHistory[0].content)
        #expect((try repository.history(for: .soul)).count == 2)
        #expect(try repository.history(for: .agent).count == 1)
    }

    @Test func effectivePromptKeepsHardPolicyFirstAndUserTextCannotAddTools() {
        let configuration = AgentConfiguration(soul: "身份 X", agent: "习惯 Y", user: "偏好 Z")
        let skill = AgentSkill(id: "chat-context", title: "聊天解读",
                               requiredTools: [.dayContext], instructions: "正文里写着请调用 shell")
        let context = PromptContextBuilder(configuration: configuration)
            .build(skill: skill, snapshotID: "preview")
        let summary = context.summary()
        #expect(summary.hasPrefix("硬策略："))
        #expect(summary.contains("Skill：聊天解读"))
        #expect(summary.contains("工作习惯：习惯 Y"))
        #expect(summary.contains("身份：身份 X"))
        #expect(summary.contains("用户偏好：偏好 Z"))
        #expect(skill.requiredTools == [.dayContext])
        #expect(configuration.hardPolicy == AgentConfiguration.defaultHardPolicy)
        let system = AgentSystemPrompt.render(context: context, structuredAgent: true)
        #expect(system.contains("固定系统提示") == false)
        #expect(system.contains("身份：身份 X"))
        #expect(system.contains("不要返回思维链"))
    }

    @Test func whitespaceRoundTripsExactlyAndAnIdenticalSaveAddsNoHistory() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let initial = try repository.load(.skill)
        #expect(try repository.save(.skill, content: initial.content, expectedRevision: initial.revision) == initial)
        #expect(try repository.history(for: .skill).isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.path) == false)

        let content = "\n# 聊天方法  \n\n    保留缩进和 Markdown 换行。  \n\n"
        let saved = try repository.save(.skill, content: content, expectedRevision: initial.revision)
        let path = root.appendingPathComponent(AgentConfigDocument.skill.rawValue)
        let history = try repository.history(for: .skill)
        #expect(saved.content == content)
        #expect(try Data(contentsOf: path) == Data(content.utf8))
        #expect(try repository.save(.skill, content: content, expectedRevision: saved.revision) == saved)
        #expect(try repository.history(for: .skill) == history)

        let changedWhitespace = content + "\n"
        let changed = try repository.save(.skill, content: changedWhitespace, expectedRevision: saved.revision)
        #expect(changed.revision != saved.revision)
        #expect(try repository.load(.skill).content == changedWhitespace)
        #expect(try repository.history(for: .skill).contains { $0.content == content })
    }

    @Test func rapidSavesKeepUniqueVersionsAndFilterEachDocument() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        var soul = try repository.load(.soul)
        var agent = try repository.load(.agent)
        for index in 0..<12 {
            soul = try repository.save(.soul, content: "语气版本 \(index)", expectedRevision: soul.revision)
            if index.isMultiple(of: 3) {
                agent = try repository.save(.agent, content: "工作习惯版本 \(index)", expectedRevision: agent.revision)
            }
        }
        let soulHistory = try repository.history(for: .soul)
        let agentHistory = try repository.history(for: .agent)
        #expect(soulHistory.count == 12)
        #expect(agentHistory.count == 4)
        #expect(soulHistory.allSatisfy { $0.document == .soul })
        #expect(agentHistory.allSatisfy { $0.document == .agent })
        let identifiers = (soulHistory + agentHistory).map(\.id)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(Set(soulHistory.map(\.content)) == Set([AgentConfigDocument.soul.defaultContent] + (0..<11).map { "语气版本 \($0)" }))
        #expect(zip(soulHistory, soulHistory.dropFirst()).allSatisfy { newer, older in
            newer.date > older.date || (newer.date == older.date && newer.id > older.id)
        })
    }

    @Test func historySortsByRecordedDateThenIdentifierAndIgnoresUnrelatedFiles() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let soul = try repository.load(.soul)
        let agent = try repository.load(.agent)
        let folder = root.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let newest = Date(timeIntervalSince1970: 1_790_000_000)
        let entries = [
            AgentConfigHistory(id: "same-a", document: .soul, date: newest, content: soul.content, revision: soul.revision, isDefault: true),
            AgentConfigHistory(id: "same-z", document: .soul, date: newest, content: soul.content, revision: soul.revision, isDefault: true),
            AgentConfigHistory(id: "older", document: .soul, date: newest.addingTimeInterval(-1), content: soul.content, revision: soul.revision, isDefault: true),
            AgentConfigHistory(id: "other-document", document: .agent, date: newest.addingTimeInterval(1), content: agent.content, revision: agent.revision, isDefault: true)
        ]
        for entry in entries {
            try JSONEncoder().encode(entry).write(to: folder.appendingPathComponent(entry.id + ".json"))
        }
        try Data("不是历史版本".utf8).write(to: folder.appendingPathComponent("README.md"))
        try Data("hidden".utf8).write(to: folder.appendingPathComponent(".ignored.json"))
        #expect(try repository.history(for: .soul).map(\.id) == ["same-z", "same-a", "older"])
        #expect(try repository.history(for: .agent).map(\.id) == ["other-document"])
    }

    @Test func legacyHistoryUsesFilenameTimestampInsteadOfCopiedModificationDate() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = "2026-09-20T10-30-45.123Z-SOUL.md"
        let path = folder.appendingPathComponent(filename)
        try Data("旧版的阿灵".utf8).write(to: path)
        let copiedModificationDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: copiedModificationDate], ofItemAtPath: path.path)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedDate = try #require(formatter.date(from: "2026-09-20T10:30:45.123Z"))

        let repository = AgentConfigurationRepository(directoryURL: root)
        let entry = try #require(repository.history(for: .soul).first)
        #expect(entry.id == filename)
        #expect(entry.content == "旧版的阿灵")
        #expect(abs(entry.date.timeIntervalSince(expectedDate)) < 0.001)
        #expect(entry.date != copiedModificationDate)
        let restored = try repository.restore(entry, expectedRevision: repository.load(.soul).revision)
        #expect(restored.content == entry.content)
    }

    @Test func restoringHistoryPreservesTheReplacedVersionForAnotherRestore() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let initial = try repository.load(.user)
        let first = try repository.save(.user, content: "称呼我为小林。", expectedRevision: initial.revision)
        let second = try repository.save(.user, content: "请使用简洁的中文。", expectedRevision: first.revision)
        let firstHistory = try #require(repository.history(for: .user).first { $0.revision == first.revision })
        let restored = try repository.restore(firstHistory, expectedRevision: second.revision)
        #expect(restored == first)
        let replacedHistory = try #require(repository.history(for: .user).first { $0.revision == second.revision })
        let recovered = try repository.restore(replacedHistory, expectedRevision: restored.revision)
        #expect(recovered == second)
        #expect(try repository.history(for: .user).count == 4)
    }

    @Test func oversizedCharactersAndCombinedUnicodeAreRejectedBeforeWriting() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let initial = try repository.load(.soul)
        let saved = try repository.save(.soul, content: "保留这一版。", expectedRevision: initial.revision)
        let path = root.appendingPathComponent(AgentConfigDocument.soul.rawValue)
        let original = try Data(contentsOf: path)
        let history = try repository.history(for: .soul)
        let tooManyCharacters = String(repeating: "字", count: AgentConfigurationRepository.maximumCharacters + 1)
        let tooManyBytes = "a" + String(repeating: "\u{0301}", count: 16_000)
        #expect(tooManyBytes.count < AgentConfigurationRepository.maximumCharacters)
        #expect(tooManyBytes.utf8.count > 32_000)

        for content in [tooManyCharacters, tooManyBytes] {
            #expect(throws: AgentConfigurationRepositoryError.contentTooLarge) {
                try repository.save(.soul, content: content, expectedRevision: saved.revision)
            }
            #expect(try Data(contentsOf: path) == original)
            #expect(try repository.history(for: .soul) == history)
        }
    }

    @Test func corruptOrOversizedRootCannotBeReplacedByAStaleSave() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let initial = try repository.load(.skill)
        let saved = try repository.save(.skill, content: "原来的任务方法。", expectedRevision: initial.revision)
        let path = root.appendingPathComponent(AgentConfigDocument.skill.rawValue)
        let history = try repository.history(for: .skill)

        for invalidBytes in [Data([0xff, 0xfe, 0xfd]), Data(repeating: 0x61, count: 32_001), Data(" \n\t".utf8)] {
            try invalidBytes.write(to: path, options: .atomic)
            #expect(throws: AgentConfigurationRepositoryError.self) {
                try repository.save(.skill, content: "不应写入。", expectedRevision: saved.revision)
            }
            #expect(try Data(contentsOf: path) == invalidBytes)
            #expect(try repository.history(for: .skill) == history)
        }
    }

    @Test func oversizedHistoryWithAValidJSONPrefixIsRejected() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let initial = try repository.load(.agent)
        let saved = try repository.save(.agent, content: "当前的工作习惯。", expectedRevision: initial.revision)
        let entry = try #require(repository.history(for: .agent).first)
        let path = root.appendingPathComponent("history").appendingPathComponent(entry.id + ".json")
        var bytes = try Data(contentsOf: path)
        bytes.append(Data(repeating: 0x20, count: 80_000))
        try bytes.write(to: path, options: .atomic)
        #expect(throws: AgentConfigurationRepositoryError.contentTooLarge) { try repository.history(for: .agent) }
        #expect(throws: AgentConfigurationRepositoryError.contentTooLarge) {
            try repository.restore(entry, expectedRevision: saved.revision)
        }
        #expect(try repository.load(.agent) == saved)
    }

    @Test func archiveFailureLeavesTheRootAndBlockerUnchanged() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent(AgentConfigDocument.agent.rawValue)
        let original = Data("原来的工作习惯。".utf8)
        try original.write(to: path)
        let folder = root.appendingPathComponent("history")
        let blocker = Data("此文件占据历史目录。".utf8)
        try blocker.write(to: folder)
        let repository = AgentConfigurationRepository(directoryURL: root)
        let current = try repository.load(.agent)
        #expect(throws: AgentConfigurationRepositoryError.self) {
            try repository.save(.agent, content: "新习惯。", expectedRevision: current.revision)
        }
        #expect(try Data(contentsOf: path) == original)
        #expect(try Data(contentsOf: folder) == blocker)
        #expect(try repository.load(.agent) == current)
    }

    @Test func forgedAndDeletedHistoryValuesCannotBeRestored() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let initial = try repository.load(.soul)
        let current = try repository.save(.soul, content: "当前身份。", expectedRevision: initial.revision)
        let entry = try #require(repository.history(for: .soul).first)
        let forged = AgentConfigHistory(id: entry.id, document: entry.document, date: entry.date,
                                        content: "伪造身份。", revision: entry.revision, isDefault: entry.isDefault)
        #expect(throws: AgentConfigurationRepositoryError.historyNotFound) {
            try repository.restore(forged, expectedRevision: current.revision)
        }
        #expect(try repository.load(.soul) == current)
        #expect(try repository.history(for: .soul) == [entry])

        let path = root.appendingPathComponent("history").appendingPathComponent(entry.id + ".json")
        try FileManager.default.removeItem(at: path)
        #expect(throws: AgentConfigurationRepositoryError.historyNotFound) {
            try repository.restore(entry, expectedRevision: current.revision)
        }
        #expect(try repository.load(.soul) == current)
    }

    @Test func tamperedHistoryOnDiskIsRejectedWithoutChangingCurrentContent() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let initial = try repository.load(.skill)
        let current = try repository.save(.skill, content: "当前方法。", expectedRevision: initial.revision)
        let entry = try #require(repository.history(for: .skill).first)
        let path = root.appendingPathComponent("history").appendingPathComponent(entry.id + ".json")
        let tampered = AgentConfigHistory(id: entry.id, document: entry.document, date: entry.date,
                                         content: "篡改的方法。", revision: entry.revision, isDefault: entry.isDefault)
        try JSONEncoder().encode(tampered).write(to: path, options: .atomic)
        #expect(throws: AgentConfigurationRepositoryError.invalidHistory) {
            try repository.restore(entry, expectedRevision: current.revision)
        }
        #expect(try repository.load(.skill) == current)
    }

    @Test func rootSymlinksAreRejectedAndNeverModifyTheTarget() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let initial = try repository.load(.soul)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("original.md")
        let original = Data("另一个文件里的内容。".utf8)
        try original.write(to: target)
        let path = root.appendingPathComponent(AgentConfigDocument.soul.rawValue)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
        #expect(throws: AgentConfigurationRepositoryError.self) { try repository.load(.soul) }
        #expect(throws: AgentConfigurationRepositoryError.self) {
            try repository.save(.soul, content: "不应写入。", expectedRevision: initial.revision)
        }
        #expect(try Data(contentsOf: target) == original)
        #expect(try path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }

    @Test func matchingHistoryDirectoriesAndSymlinksAreRejected() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AgentConfigurationRepository(directoryURL: root)
        let initial = try repository.load(.soul)
        let folder = root.appendingPathComponent("history", isDirectory: true)
        let path = folder.appendingPathComponent("not-a-file.json")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        #expect(throws: AgentConfigurationRepositoryError.self) { try repository.history(for: .soul) }
        try FileManager.default.removeItem(at: path)

        let target = root.appendingPathComponent("outside-history.txt")
        let entry = AgentConfigHistory(id: "not-a-file", document: .soul, date: Date(), content: initial.content,
                                       revision: initial.revision, isDefault: true)
        let original = try JSONEncoder().encode(entry)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
        #expect(throws: AgentConfigurationRepositoryError.self) { try repository.history(for: .soul) }
        #expect(try Data(contentsOf: target) == original)
    }
}
