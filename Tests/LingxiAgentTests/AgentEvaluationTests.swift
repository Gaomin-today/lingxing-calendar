import Foundation
import Testing
@testable import LingxiAgent

struct AgentEvaluationTests {
    @Test func fixedSyntheticSuiteRunsAllFortyOneDistinctChecks() async {
        let report = await AgentEvaluationSuite.run()
        #expect(AgentEvaluationSuite.caseCount == 41)
        #expect(report.cancelled == false)
        #expect(report.totalCount == 41)
        #expect(report.passedCount == 41, "失败：\(report.results.filter { !$0.passed }.map { $0.id + ": " + $0.detail }.joined(separator: "; "))")
        #expect(report.failedCount == 0)
        #expect(Set(report.results.map(\.id)).count == 41)
        #expect(Set(report.results.map(\.title)).count == 41)
        #expect(report.endedAt >= report.startedAt)
        #expect(report.results.allSatisfy { !$0.detail.isEmpty && $0.duration >= 0 && $0.duration.isFinite })
        let expected: [AgentEvaluationCategory: Int] = [.facts: 10, .chartKnowledge: 10, .missingData: 5,
                                                       .conflicts: 5, .localWrites: 5, .repeatedRequests: 3,
                                                       .cancellationTimeout: 3]
        for category in AgentEvaluationCategory.allCases {
            #expect(report.results.filter { $0.category == category }.count == expected[category])
        }
        #expect(report.results.first?.id == "fact.lunar-new-year")
        #expect(report.results.last?.id == "interrupt.model-timeout")
        #expect(report.results.contains { $0.id == "write.undo-event" && $0.passed })
        #expect(report.results.contains { $0.id == "conflict.two-revisions" && $0.passed })
    }

    @Test func aCancelledSuiteStopsBeforeExecutingAnyCase() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await AgentEvaluationSuite.run()
        }
        let report = await task.value
        #expect(report.cancelled)
        #expect(report.results.isEmpty)
        #expect(report.totalCount == 0)
        #expect(report.passedCount == 0)
        #expect(report.failedCount == 0)
    }
}
