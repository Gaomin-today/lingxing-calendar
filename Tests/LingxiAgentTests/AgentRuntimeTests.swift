import Foundation
import Testing
@testable import LingxiAgent
import LingxiCore

struct AgentRuntimeTests {
    @Test func actionProposalRoundTripsTheExactConfirmedRequest() throws {
        let request = AutomationRequest(requestID: "save-42", method: "journal.create",
                                        params: .object(["date": .string("2026-09-21"), "body": .string("今天完成了复盘")]))
        let proposal = AgentActionProposal(kind: "journal", title: "保存到日笺",
                                            summary: "将这次解读保存到本地", request: request)

        let data = try JSONEncoder().encode(proposal)
        let decoded = try JSONDecoder().decode(AgentActionProposal.self, from: data)
        #expect(decoded == proposal)
        #expect(decoded.id == "save-42")
        #expect(decoded.request.method == "journal.create")
        #expect(decoded.request.params["body"]?.stringValue == "今天完成了复盘")
    }

    @Test func actionReceiptIdentityAndRevisionSurviveReplay() throws {
        let receipt = AgentActionReceipt(requestID: "save-42", method: "journal.create",
                                         entity: "notes", entityID: "note-7", revision: "rev-3")
        let data = try JSONEncoder().encode(receipt)
        let decoded = try JSONDecoder().decode(AgentActionReceipt.self, from: data)
        #expect(decoded == receipt)
        #expect(decoded.id == "save-42")
        #expect(decoded.revision == "rev-3")
    }

    actor CallState {
        var count = 0
        func next() -> Int { count += 1; return count }
    }

    private func toolRegistry() -> TypedToolRegistry {
        let value = AgentToolResult(callID: "", name: .dayContext,
                                    payload: .object(["date": .string("2026-09-20"), "timeZone": .string("Asia/Shanghai")]),
                                    sourceRef: "day:2026-09-20", sourceRevision: "day-r1")
        return TypedToolRegistry(provider: InMemoryToolProvider(values: [.dayContext: value]))
    }

    @Test func deepLoopReadsTypedToolAndCitesRevision() async throws {
        let state = CallState()
        let model = ClosureModelGateway { request in
            let call = await state.next()
            if call == 1 {
                return AgentModelResponse(toolCalls: [AgentToolCall(name: .dayContext, arguments: ["date": .string("2026-09-20")])], finished: false)
            }
            let claim = AgentClaim(text: "应用返回的日期是 2026-09-20。", sourceRef: "day:2026-09-20", sourceRevision: "day-r1", evidenceType: .deterministicFact, confidence: 1)
            return AgentModelResponse(text: "今天的日期依据已经核对。", claims: [claim])
        }
        let skill = AgentSkill(id: "test-skill", title: "测试解读", requiredTools: [.dayContext])
        let runtime = AgentRuntime(driver: model, tools: toolRegistry(), skillRegistry: SkillRegistry(skills: [skill]))
        let result = try await runtime.run(AgentRequest(requestID: "test-deep", text: "严谨核对今天的日期", mode: .deep))
        #expect(result.answer.degraded == false)
        #expect(result.answer.critic.passed)
        #expect(result.ledger.records.contains { $0.sourceRef == "day:2026-09-20" && $0.sourceRevision == "day-r1" })
        #expect(result.answer.evidence.contains { $0.claim.contains("2026-09-20") })
        #expect(result.statuses.contains { $0.phase == .retrieve })
        let trace = await runtime.trace(result.traceID)
        #expect(trace?.toolCalls == 1)
        #expect(trace?.modelCalls == 2)
        #expect(trace?.events.contains { $0.phase == .retrieve } == true)
    }

    @Test func unsourcedClaimIsMarkedUncertainWithoutThrowing() async throws {
        let model = ClosureModelGateway { _ in AgentModelResponse(text: "这是一个没有依据的判断。", claims: [AgentClaim(text: "无来源断言")]) }
        let runtime = AgentRuntime(driver: model, tools: TypedToolRegistry())
        let result = try await runtime.run(AgentRequest(requestID: "test-uncertain", text: "给我一个建议", mode: .quick))
        #expect(result.answer.degraded)
        #expect(result.answer.critic.unsupportedClaims.contains("无来源断言"))
        #expect(result.answer.uncertainty.contains("无来源断言"))
    }

    @Test func registryRejectsToolOutsideAllowlistAndBoundsPayload() async throws {
        let registry = TypedToolRegistry(handlers: [.dayContext: { call in
            AgentToolResult(callID: call.id, name: .dayContext, payload: .string(String(repeating: "x", count: 2_000)), sourceRef: "day")
        }], maximumPayloadCharacters: 100)
        do { _ = try await registry.read(AgentToolCall(name: .eventsContext)); Issue.record("unlisted tool succeeded") }
        catch is AgentToolError { }
        catch { Issue.record("unexpected error: \(error)") }
        do { _ = try await registry.read(AgentToolCall(name: .dayContext)); Issue.record("oversized tool succeeded") }
        catch is AgentToolError { }
        catch { Issue.record("unexpected error: \(error)") }
    }

    @Test func modelTimeoutStopsTheLoop() async throws {
        let model = ClosureModelGateway { _ in
            try await Task.sleep(nanoseconds: 500_000_000)
            return AgentModelResponse(text: "late")
        }
        let runtime = AgentRuntime(driver: model, tools: TypedToolRegistry(), budget: AgentBudget(maxModelCalls: 2, timeoutSeconds: 0.05))
        let result = try await runtime.run(AgentRequest(requestID: "test-timeout", text: "快速回答", mode: .quick))
        #expect(result.answer.degraded)
        #expect(result.statuses.contains { $0.phase == .final })
    }

    @Test func cancellationStopsBeforeASecondModelTurn() async throws {
        let model = ClosureModelGateway { _ in
            try await Task.sleep(nanoseconds: 100_000_000)
            return AgentModelResponse(text: "late")
        }
        let runtime = AgentRuntime(driver: model, tools: TypedToolRegistry(), budget: AgentBudget(maxModelCalls: 2, timeoutSeconds: 1))
        let task = Task { try await runtime.run(AgentRequest(requestID: "test-cancel", text: "请核对", mode: .deep)) }
        try await Task.sleep(nanoseconds: 10_000_000)
        await runtime.cancel(requestID: "test-cancel")
        do {
            _ = try await task.value
            Issue.record("cancelled run unexpectedly succeeded")
        } catch AgentRuntimeError.cancelled { }
        catch { Issue.record("unexpected error: \(error)") }
    }

    @Test func structuredAssistantEnvelopeKeepsSourceAndToolArguments() {
        let text = """
        ```json
        {"conclusion":"按已核验事实回答。","claims":[{"text":"今天为甲子日。","sourceRef":"day:2026-09-21","sourceRevision":"r1","evidenceType":"deterministicFact","confidence":0.9}],"toolCalls":[{"id":"k1","name":"knowledge_search","arguments":{"query":"日常建议"}}],"critic":{"passed":false,"missingEvidence":["还需读取知识"],"needsSupplementalRead":true}}
        ```
        """
        let response = AgentResponseCodec.decode(text)
        #expect(response.text == "按已核验事实回答。")
        #expect(response.claims.count == 1)
        #expect(response.claims.first?.sourceRef == "day:2026-09-21")
        #expect(response.claims.first?.sourceRevision == "r1")
        #expect(response.toolCalls.first?.name == .knowledgeSearch)
        #expect(response.toolCalls.first?.arguments["query"]?.stringValue == "日常建议")
        #expect(response.critic?.passed == false)
        #expect(response.critic?.needsSupplementalRead == true)
    }

    @Test func malformedStructuredAssistantTextFallsBackToPlainConclusion() {
        let response = AgentResponseCodec.decode("{这不是有效 JSON}")
        #expect(response.text == "{这不是有效 JSON}")
        #expect(response.claims.isEmpty)
        #expect(response.toolCalls.isEmpty)
    }
}
