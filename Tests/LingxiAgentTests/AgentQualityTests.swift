import Foundation
import Testing
@testable import LingxiAgent
import LingxiCore

struct AgentQualityTests {
    private func reference(source: String = "day:today", revision: String? = "r1",
                           type: EvidenceType = .deterministicFact) -> AgentToolResult {
        AgentToolResult(callID: "read", name: .dayContext, payload: .object(["date": .string("2026-09-28")]),
                        sourceRef: source, sourceRevision: revision, evidenceType: type)
    }

    private func fact(id: String = "fact", source: String? = "day:today", revision: String? = "r1",
                      type: EvidenceType = .deterministicFact) -> AgentClaim {
        AgentClaim(id: id, text: "这是一条结构化声明。", sourceRef: source, sourceRevision: revision,
                   evidenceType: type)
    }

    private func registry() -> TypedToolRegistry {
        TypedToolRegistry(provider: InMemoryToolProvider(values: [.dayContext: reference()]))
    }

    @Test func coverageMeasuresOnlyExplicitFactAndKnowledgeClaims() {
        let claims = [fact(), fact(id: "knowledge", source: "book", type: .knowledgeText),
                      fact(id: "missing", source: nil), fact(id: "inference", type: .modelInference),
                      fact(id: "user", type: .userInput)]
        let report = AgentQualityReport.evaluate(claims: claims,
                                                 references: [reference(), reference(source: "book", type: .knowledgeText)])
        #expect(report.claims.count == 5)
        #expect(report.factClaimCount == 3)
        #expect(report.citedFactCount == 2)
        #expect(report.citationCoverage == 2.0 / 3.0)
        #expect(report.claims[3].status == .modelInference)
        #expect(report.claims[4].status == .userInput)
        #expect(report.claims[3].isCited == false)
        #expect(report.claims[4].isCited == false)
    }

    @Test func emptyClaimsOrUnscoredStatementsHaveUnknownCoverage() {
        for claims in [[], [fact(type: .modelInference), fact(id: "user", type: .userInput)]] {
            let report = AgentQualityReport.evaluate(claims: claims, references: [reference()])
            #expect(report.factClaimCount == 0)
            #expect(report.citedFactCount == 0)
            #expect(report.citationCoverage == nil)
        }
    }

    @Test func missingSourceAndMissingRevisionAreDifferentFailures() {
        let cases: [(AgentClaim, AgentClaimCitationStatus)] = [
            (fact(source: nil), .missingSource),
            (fact(source: " \n"), .missingSource),
            (fact(source: "unread"), .sourceNotFound),
            (fact(source: "day:today "), .sourceNotFound),
            (fact(revision: nil), .missingRevision),
            (fact(revision: " \n"), .missingRevision),
            (fact(revision: "old"), .staleRevision),
            (fact(revision: "r1 "), .staleRevision)
        ]
        for (claim, status) in cases {
            let report = AgentQualityReport.evaluate(claims: [claim], references: [reference()])
            #expect(report.claims[0].status == status)
            #expect(report.citationCoverage == 0)
        }
    }

    @Test func absentSourceRevisionsAndConflictsCannotBeCited() {
        for revision in [nil, "", " \n"] as [String?] {
            let report = AgentQualityReport.evaluate(claims: [fact()], references: [reference(revision: revision)])
            #expect(report.claims[0].status == .sourceRevisionMissing)
            #expect(report.citedFactCount == 0)
        }
        for secondRevision in ["r2", nil] as [String?] {
            let report = AgentQualityReport.evaluate(claims: [fact()], references: [reference(), reference(revision: secondRevision)])
            #expect(report.claims[0].status == .conflictingRevisions)
            #expect(report.citedFactCount == 0)
        }
    }

    @Test func sourceTypeMustMatchEvenWhenSourceAndRevisionMatch() {
        let report = AgentQualityReport.evaluate(claims: [fact(type: .knowledgeText)], references: [reference()])
        #expect(report.claims[0].status == .typeMismatch)
        #expect(report.citationCoverage == 0)
        let ambiguous = AgentQualityReport.evaluate(claims: [fact()], references: [reference(), reference(type: .knowledgeText)])
        #expect(ambiguous.claims[0].status == .typeMismatch)
    }

    @Test func duplicateReadsDoNotInflateCoverageAndDuplicateClaimIDsRemainDistinct() {
        var second = fact()
        second.text = "另一条声明。"
        let claims = [fact(), second]
        let report = AgentQualityReport.evaluate(claims: claims, references: [reference(), reference(), reference()])
        #expect(report.factClaimCount == 2)
        #expect(report.citedFactCount == 2)
        #expect(report.citationCoverage == 1)
        #expect(Set(report.claims.map(\.id)).count == 2)
        #expect(report == AgentQualityReport.evaluate(claims: claims, references: [reference()]))
    }

    @Test func reportsRoundTripAndOldRunResultsDecodeWithoutQuality() throws {
        let report = AgentQualityReport.evaluate(claims: [fact()], references: [reference()])
        #expect(try JSONDecoder().decode(AgentQualityReport.self, from: JSONEncoder().encode(report)) == report)
        let result = AgentRunResult(requestID: "legacy", answer: AgentAnswer(conclusion: "回答", mode: .quick),
                                    ledger: EvidenceLedger(), traceID: "trace", quality: report)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        object.removeValue(forKey: "quality")
        let decoded = try JSONDecoder().decode(AgentRunResult.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.quality == nil)
        #expect(decoded.requestID == "legacy")
    }

    @Test func runtimeRejectsMissingRevisionAndWrongTypeDespiteModelPassingCritic() async throws {
        let claims = [fact(revision: nil), fact(type: .knowledgeText)]
        for claim in claims {
            let model = ClosureModelGateway { request in
                if request.step == 1 {
                    return AgentModelResponse(toolCalls: [AgentToolCall(name: .dayContext)], finished: false)
                }
                return AgentModelResponse(text: "模型声称已校验。", claims: [claim], critic: AgentCriticReport(passed: true))
            }
            let runtime = AgentRuntime(driver: model, tools: registry(), skillRegistry: SkillRegistry(skills: []))
            let result = try await runtime.run(AgentRequest(text: "核对声明", mode: .quick))
            #expect(result.answer.critic.passed == false)
            #expect(result.answer.degraded)
            #expect(result.quality?.citedFactCount == 0)
            #expect(result.ledger.records.contains { $0.claim == claim.text } == false)
            #expect(result.ledger.records.count == 1)
        }
    }

    @Test func runtimeUsesRawClaimsRatherThanGenericLedgerEntriesForQuality() async throws {
        let model = ClosureModelGateway { request in
            if request.step == 1 {
                return AgentModelResponse(toolCalls: [AgentToolCall(name: .dayContext)], finished: false)
            }
            return AgentModelResponse(text: "没有结构化声明的普通回答。")
        }
        let runtime = AgentRuntime(driver: model, tools: registry(), skillRegistry: SkillRegistry(skills: []))
        let result = try await runtime.run(AgentRequest(text: "回答", mode: .quick))
        let quality = try #require(result.quality)
        #expect(result.ledger.records.count == 1)
        #expect(result.ledger.records[0].claim.hasPrefix("已读取"))
        #expect(quality.factClaimCount == 0)
        #expect(quality.citationCoverage == nil)
    }

    @Test func finalClaimsAreCheckedEvenWhenToolBudgetStopsTheLoop() async throws {
        let claim = fact()
        let model = ClosureModelGateway { _ in
            AgentModelResponse(text: "工具尚未执行的声明。",
                               toolCalls: [AgentToolCall(name: .dayContext), AgentToolCall(name: .dayContext)],
                               claims: [claim], critic: AgentCriticReport(passed: true))
        }
        let runtime = AgentRuntime(driver: model, tools: registry(), skillRegistry: SkillRegistry(skills: []),
                                   budget: AgentBudget(maxToolCalls: 1, maxModelCalls: 1))
        let result = try await runtime.run(AgentRequest(text: "回答", mode: .quick))
        #expect(result.answer.critic.passed == false)
        #expect(result.quality?.claims.first?.status == .sourceNotFound)
        #expect(result.ledger.records.isEmpty)
    }

    @Test func runtimeBindsDistinctValidClaimsWithDuplicateModelIDs() async throws {
        var second = fact()
        second.text = "同一来源的第二条声明。"
        let claims = [fact(), second]
        let model = ClosureModelGateway { request in
            if request.step == 1 { return AgentModelResponse(toolCalls: [AgentToolCall(name: .dayContext)], finished: false) }
            return AgentModelResponse(text: "两条声明。", claims: claims)
        }
        let runtime = AgentRuntime(driver: model, tools: registry(), skillRegistry: SkillRegistry(skills: []))
        let result = try await runtime.run(AgentRequest(text: "回答", mode: .quick))
        #expect(result.quality?.citedFactCount == 2)
        #expect(result.answer.critic.passed)
        #expect(result.ledger.records.count == 3)
        #expect(Set(result.ledger.records.map(\.claimID)).count == 3)
        #expect(claims.allSatisfy { claim in result.ledger.records.contains { $0.claim == claim.text } })
    }

    @Test(arguments: [false, true])
    func unfinishedRepairRetainsEarlierCriticProblemsWhenModelBudgetEnds(finished: Bool) async throws {
        let claim = fact()
        let model = ClosureModelGateway { request in
            if request.step == 1 {
                return AgentModelResponse(text: "尚未取得来源的初稿。", claims: [claim],
                                           critic: AgentCriticReport(passed: false, missingEvidence: ["仍需复核盘面"],
                                                                    needsSupplementalRead: true))
            }
            return AgentModelResponse(toolCalls: [AgentToolCall(name: .dayContext)], finished: finished)
        }
        let runtime = AgentRuntime(driver: model, tools: registry(), skillRegistry: SkillRegistry(skills: []),
                                   budget: AgentBudget(maxModelCalls: 2))
        let result = try await runtime.run(AgentRequest(text: "严谨核对", mode: .deep))
        #expect(result.answer.degraded)
        #expect(result.answer.critic.passed == false)
        #expect(result.answer.critic.missingEvidence.contains("仍需复核盘面"))
        #expect(result.answer.uncertainty.contains("仍需复核盘面"))
        #expect(result.quality?.citationCoverage == nil)
        #expect(result.ledger.records.count == 1)
        let trace = try #require(await runtime.trace(result.traceID))
        #expect(trace.modelCalls == 2)
        #expect(trace.critic?.passed == false)
        #expect(trace.critic?.missingEvidence.contains("仍需复核盘面") == true)
    }

    @Test func completedRepairMayReadToolsAndReplaceEarlierCriticProblems() async throws {
        let claim = fact()
        let model = ClosureModelGateway { request in
            if request.step == 1 {
                return AgentModelResponse(text: "缺少来源的初稿。", claims: [claim])
            }
            return AgentModelResponse(text: "已补读来源的新回答。", toolCalls: [AgentToolCall(name: .dayContext)],
                                       claims: [claim], finished: true)
        }
        let runtime = AgentRuntime(driver: model, tools: registry(), skillRegistry: SkillRegistry(skills: []),
                                   budget: AgentBudget(maxModelCalls: 2))
        let result = try await runtime.run(AgentRequest(text: "严谨核对", mode: .deep))
        #expect(result.answer.critic.passed)
        #expect(result.answer.critic.missingEvidence.isEmpty)
        #expect(result.quality?.citationCoverage == 1)
        #expect(result.ledger.records.contains { $0.claim == claim.text })
    }

    private actor ChangingSource {
        var reads = 0
        func read(_ call: AgentToolCall) -> AgentToolResult {
            reads += 1
            return AgentToolResult(callID: call.id, name: call.name, payload: .string("事实来源"),
                                   sourceRef: "day:today", sourceRevision: "r\(reads)")
        }
    }

    @Test func conflictingVersionsRemainUncitedAfterASecondRead() async throws {
        let source = ChangingSource()
        let tools = TypedToolRegistry(handlers: [.dayContext: { call in await source.read(call) }])
        let claim = fact(revision: "r2")
        let model = ClosureModelGateway { request in
            if request.step <= 2 { return AgentModelResponse(toolCalls: [AgentToolCall(name: .dayContext)], finished: false) }
            return AgentModelResponse(text: "来源冲突。", claims: [claim], critic: AgentCriticReport(passed: true))
        }
        let runtime = AgentRuntime(driver: model, tools: tools, skillRegistry: SkillRegistry(skills: []),
                                   budget: AgentBudget(maxModelCalls: 3))
        let result = try await runtime.run(AgentRequest(text: "严谨核对", mode: .deep))
        #expect(result.quality?.claims.first?.status == .conflictingRevisions)
        #expect(result.answer.critic.passed == false)
        #expect(result.answer.critic.conflicts.contains("day:today"))
        #expect(result.ledger.records.contains { $0.claim == claim.text } == false)
    }

    @Test func contradictoryModelCriticCannotPassWithReportedProblems() async throws {
        let model = ClosureModelGateway { _ in
            AgentModelResponse(text: "还缺资料。", critic: AgentCriticReport(passed: true, missingEvidence: ["缺少盘面"]))
        }
        let runtime = AgentRuntime(driver: model, tools: TypedToolRegistry(), skillRegistry: SkillRegistry(skills: []))
        let result = try await runtime.run(AgentRequest(text: "回答", mode: .quick))
        #expect(result.answer.critic.passed == false)
        #expect(result.answer.uncertainty.contains("缺少盘面"))
    }

    @Test func latestTraceUsesStartTimeAndFiltersRequestID() async {
        let store = TraceStore()
        let latest = await store.begin(requestID: "same", mode: .quick, at: Date(timeIntervalSince1970: 20))
        let older = await store.begin(requestID: "same", mode: .deep, at: Date(timeIntervalSince1970: 10))
        await store.finish(older.id, at: Date(timeIntervalSince1970: 100))
        _ = await store.begin(requestID: "other", mode: .quick, at: Date(timeIntervalSince1970: 200))
        #expect(await store.latest(requestID: "same")?.id == latest.id)
        #expect(await store.latest(requestID: "unknown") == nil)
    }

    @Test func runtimeRetainsModelAndFindableFailureTrace() async throws {
        let runtime = AgentRuntime(driver: ClosureModelGateway { _ in AgentModelResponse(text: "回答") },
                                   tools: TypedToolRegistry(), skillRegistry: SkillRegistry(skills: []), modelName: "test-model")
        let success = try await runtime.run(AgentRequest(requestID: "success", text: "回答"))
        #expect(await runtime.trace(success.traceID)?.model == "test-model")
        await runtime.cancel(requestID: "cancelled")
        do {
            _ = try await runtime.run(AgentRequest(requestID: "cancelled", text: "已取消"))
            Issue.record("cancelled run returned")
        } catch AgentRuntimeError.cancelled { }
        let failure = try #require(await runtime.latestTrace(requestID: "cancelled"))
        #expect(failure.model == "test-model")
        #expect(failure.failure == AgentRuntimeError.cancelled.localizedDescription)
        #expect(failure.endedAt != nil)
    }
}
