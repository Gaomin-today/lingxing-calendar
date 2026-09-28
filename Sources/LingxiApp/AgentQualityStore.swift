import Combine
import Foundation
import LingxiAgent

/// Session-only inspection data. No prompts, credentials or tool payloads are
/// added here; the user can remove these summaries without changing a reply.
struct AgentRunInspection: Identifiable {
    let id: String
    let result: AgentRunResult?
    let trace: AgentTrace?
    let model: String
    let finishedAt: Date
    let failure: String?
}

@MainActor final class AgentQualityStore: ObservableObject {
    @Published private(set) var records: [AgentRunInspection] = []
    @Published private(set) var evaluation: AgentEvaluationReport?
    @Published private(set) var isEvaluating = false
    private var evaluationTask: Task<Void, Never>?
    private let evaluationRunner: @Sendable () async -> AgentEvaluationReport

    init(evaluationRunner: @escaping @Sendable () async -> AgentEvaluationReport = { await AgentEvaluationSuite.run() }) {
        self.evaluationRunner = evaluationRunner
    }

    func record(requestID: String, result: AgentRunResult?, trace: AgentTrace?, model: String,
                failure: String? = nil) {
        records.removeAll { $0.id == requestID }
        records.insert(AgentRunInspection(id: requestID, result: result, trace: trace, model: model,
                                         finishedAt: Date(), failure: failure), at: 0)
        if records.count > 30 { records.removeLast(records.count - 30) }
    }

    func clearRecords() { records.removeAll() }
    func removeRecord(id: String) { records.removeAll { $0.id == id } }

    func runEvaluations() {
        guard !isEvaluating else { return }
        isEvaluating = true
        evaluation = nil
        let runner = evaluationRunner
        evaluationTask = Task { [weak self] in
            let report = await runner()
            guard let self else { return }
            self.evaluation = report
            self.isEvaluating = false
            self.evaluationTask = nil
        }
    }

    func cancelEvaluations() { evaluationTask?.cancel() }
}
