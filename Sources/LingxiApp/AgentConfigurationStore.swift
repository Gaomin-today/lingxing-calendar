import CryptoKit
import Foundation
import Combine
import LingxiAgent

/// Main-actor adapter between SwiftUI and the Foundation-only configuration
/// repository. The repository owns validation, revisions and history; this
/// object only publishes current snapshots and user-visible errors.
@MainActor final class AgentConfigurationStore: ObservableObject {
    @Published private(set) var values: [AgentConfigDocument: String]
    @Published private(set) var snapshots: [AgentConfigDocument: AgentConfigSnapshot]
    @Published private(set) var history: [AgentConfigHistory] = []
    @Published private(set) var error: String?
    @Published private(set) var historyError: String?
    @Published private(set) var loadErrors: [AgentConfigDocument: String] = [:]
    let directoryURL: URL
    private let repository: AgentConfigurationRepository

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.repository = AgentConfigurationRepository(directoryURL: directoryURL)
        let initial = Dictionary(uniqueKeysWithValues: AgentConfigDocument.allCases.map {
            ($0, AgentConfigSnapshot(document: $0, content: $0.defaultContent,
                                     revision: Self.revision(of: $0.defaultContent), isDefault: true))
        })
        self.snapshots = initial
        self.values = initial.mapValues(\.content)
        load()
    }

    var configuration: AgentConfiguration {
        AgentConfiguration(soul: value(for: .soul), agent: value(for: .agent), user: value(for: .user))
    }

    func value(for document: AgentConfigDocument) -> String { snapshots[document]?.content ?? document.defaultContent }
    func revision(for document: AgentConfigDocument) -> String { snapshots[document]?.revision ?? Self.revision(of: document.defaultContent) }
    func history(for document: AgentConfigDocument) -> [AgentConfigHistory] { history.filter { $0.document == document } }

    @discardableResult
    func save(_ document: AgentConfigDocument, content: String) -> Bool {
        do {
            let saved = try repository.save(document, content: content,
                                            expectedRevision: revision(for: document))
            set(saved)
            loadErrors[document] = nil
            error = nil
            refreshHistory()
            return true
        } catch {
            self.error = message(for: error)
            refreshHistory()
            return false
        }
    }

    @discardableResult
    func restoreDefaults(_ document: AgentConfigDocument) -> Bool {
        save(document, content: document.defaultContent)
    }

    @discardableResult
    func restore(_ item: AgentConfigHistory) -> Bool {
        do {
            let restored = try repository.restore(item, expectedRevision: revision(for: item.document))
            set(restored)
            loadErrors[item.document] = nil
            error = nil
            refreshHistory()
            return true
        } catch {
            self.error = message(for: error)
            refreshHistory()
            return false
        }
    }

    private func load() {
        for document in AgentConfigDocument.allCases {
            do { set(try repository.load(document)) }
            catch { loadErrors[document] = message(for: error) }
        }
        refreshHistory()
    }

    /// Explicit reload is also the recovery path after an external edit.
    /// The view asks before replacing an unsaved draft.
    @discardableResult
    func reload(_ document: AgentConfigDocument) -> Bool {
        do {
            set(try repository.load(document))
            loadErrors[document] = nil
            error = nil
            refreshHistory()
            return true
        } catch {
            loadErrors[document] = message(for: error)
            self.error = message(for: error)
            return false
        }
    }

    private func refreshHistory() {
        var loaded: [AgentConfigHistory] = []
        var failures: [String] = []
        for document in AgentConfigDocument.allCases {
            do { loaded.append(contentsOf: try repository.history(for: document)) }
            catch { failures.append("\(document.rawValue)：\(message(for: error))") }
        }
        history = loaded.sorted { $0.date > $1.date }
        historyError = failures.isEmpty ? nil : "历史版本读取失败：" + failures.joined(separator: "；")
    }

    private func set(_ snapshot: AgentConfigSnapshot) {
        snapshots[snapshot.document] = snapshot
        values[snapshot.document] = snapshot.content
    }

    private func message(for error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }

    private static func revision(of content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
