import Foundation
import Testing
import LingxiAgent
@testable import LingxiApp

@MainActor struct AgentQualityStoreTests {
    @Test func inspectionHistoryIsBoundedAndUpdatesKeepOneRecordPerRequest() {
        let store = AgentQualityStore()
        for index in 0..<35 {
            store.record(requestID: "request-\(index)", result: nil, trace: nil, model: "synthetic")
        }
        #expect(store.records.count == 30)
        #expect(store.records.first?.id == "request-34")
        #expect(store.records.last?.id == "request-5")
        store.record(requestID: "request-20", result: nil, trace: nil, model: "updated", failure: "已停止")
        #expect(store.records.count == 30)
        #expect(store.records.first?.id == "request-20")
        #expect(store.records.first?.failure == "已停止")
        #expect(store.records.filter { $0.id == "request-20" }.count == 1)
    }

    @Test func removingInspectionDataDoesNotResurrectOlderRecords() {
        let store = AgentQualityStore()
        store.record(requestID: "first", result: nil, trace: nil, model: "synthetic")
        store.record(requestID: "second", result: nil, trace: nil, model: "synthetic")
        store.removeRecord(id: "first")
        #expect(store.records.map(\.id) == ["second"])
        store.clearRecords()
        #expect(store.records.isEmpty)
        store.record(requestID: "third", result: nil, trace: nil, model: "synthetic")
        #expect(store.records.map(\.id) == ["third"])
    }

    private actor RunCounter {
        var count = 0
        func start() { count += 1 }
        func value() -> Int { count }
    }

    @Test func onlyOneEvaluationRunsAndCancellationPublishesAPartialReport() async throws {
        let counter = RunCounter()
        let store = AgentQualityStore(evaluationRunner: {
            await counter.start()
            let started = Date()
            do { try await Task.sleep(nanoseconds: 5_000_000_000) }
            catch { }
            return AgentEvaluationReport(startedAt: started, endedAt: Date(), results: [], cancelled: Task.isCancelled)
        })
        store.runEvaluations()
        store.runEvaluations()
        #expect(store.isEvaluating)
        // Wait for the injected runner to start, without waiting its timeout.
        for _ in 0..<100 {
            if await counter.value() == 1 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(await counter.value() == 1)
        store.cancelEvaluations()
        // A cancel request must not allow a second run before cleanup ends.
        store.runEvaluations()
        for _ in 0..<100 {
            if !store.isEvaluating { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(!store.isEvaluating)
        #expect(await counter.value() == 1)
        #expect(store.evaluation?.cancelled == true)
        #expect(store.evaluation?.totalCount == 0)
    }
}
