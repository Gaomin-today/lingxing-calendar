import Foundation
import LingxiCore

public struct UnavailableModelGateway: ModelGateway {
    public init() {}
    public func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        throw AgentRuntimeError.unavailable("尚未配置可用的模型服务。")
    }
}

/// A bounded, read-only orchestration loop. The runtime owns no application
/// storage and can therefore be tested with an in-memory tool provider.
public actor AgentRuntime {
    private let driver: any ModelGateway
    private let tools: TypedToolRegistry
    private let skillRegistry: SkillRegistry
    private let contextBuilder: PromptContextBuilder
    private let traceStore: TraceStore
    private let defaultBudget: AgentBudget
    private let modelName: String?
    private var cancelled: Set<String> = []

    public init(driver: any ModelGateway, tools: TypedToolRegistry,
                skillRegistry: SkillRegistry = .init(),
                contextBuilder: PromptContextBuilder = .init(),
                traceStore: TraceStore = .init(), budget: AgentBudget = .deep,
                modelName: String? = nil) {
        self.driver = driver
        self.tools = tools
        self.skillRegistry = skillRegistry
        self.contextBuilder = contextBuilder
        self.traceStore = traceStore
        self.defaultBudget = budget
        self.modelName = modelName
    }

    /// Request cancellation. The currently running model/tool call is allowed
    /// to return, then no further call or mutation is started.
    public func cancel(requestID: String) { cancelled.insert(requestID) }

    public func trace(_ id: String) async -> AgentTrace? { await traceStore.trace(id) }
    public func latestTrace(requestID: String) async -> AgentTrace? { await traceStore.latest(requestID: requestID) }

    public func run(_ request: AgentRequest) async throws -> AgentRunResult {
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentRuntimeError.emptyRequest }
        guard !request.requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.requestID.utf8.count <= 128 else {
            throw AgentRuntimeError.unavailable("request_id 不能为空且不能超过 128 个字节。")
        }
        let mode = request.mode ?? inferredMode(request.text)
        let budget = mode == .quick ? minimumBudget(defaultBudget, .quick) : defaultBudget
        let trace = await traceStore.begin(requestID: request.requestID, mode: mode, model: modelName)
        let started = Date()
        var statuses: [AgentStatus] = []
        var ledger = EvidenceLedger()
        var references: [AgentToolResult] = []
        var messages = [AgentMessage(role: .user, content: request.text)]
        var lastResponse = AgentModelResponse()
        var critic = AgentCriticReport()
        var degraded = false
        var modelCalls = 0
        var toolCalls = 0
        var readRounds = 0
        var repairUsed = false
        var modelRetryUsed = false
        var timedOut = false
        let skill = skillRegistry.select(for: request.text)

        func status(_ phase: AgentPhase, _ message: String, _ completed: Bool = false) {
            statuses.append(AgentStatus(phase: phase, message: message, completed: completed))
        }
        func checkBudgetAndCancellation() throws {
            if cancelled.contains(request.requestID) || Task.isCancelled { throw AgentRuntimeError.cancelled }
            // A timed-out model call may still leave verified tool evidence.
            // Preserve that evidence and return a degraded answer instead of
            // turning an otherwise useful partial result into a hard failure.
            if !timedOut, Date().timeIntervalSince(started) >= budget.timeoutSeconds,
               references.isEmpty, lastResponse.text == nil {
                throw AgentRuntimeError.timeout
            }
        }

        do {
            status(.classify, "选择解读方式")
            await traceStore.append(AgentTraceEvent(phase: .classify, summary: mode == .deep ? "深度模式" : "快速模式"), to: trace.id)
            status(.loadSkill, "读取 Skill")
            if let skill { await traceStore.append(AgentTraceEvent(phase: .loadSkill, summary: skill.id), to: trace.id) }
            status(.planEvidence, "规划所需依据")
            try checkBudgetAndCancellation()

            while modelCalls < budget.maxModelCalls {
                try checkBudgetAndCancellation()
                modelCalls += 1
                let snapshotID = "\(request.requestID):\(modelCalls)"
                let context = contextBuilder.build(skill: skill, references: references, conversation: messages, snapshotID: snapshotID)
                let modelRequest = AgentModelRequest(requestID: request.requestID, step: modelCalls, mode: mode,
                                                     messages: messages, context: context)
                status(modelCalls == 1 ? .draft : (repairUsed ? .repair : .critic), modelCalls == 1 ? "整理初稿" : "补读并复核")
                // Count one redacted trace event per model call. The user-facing
                // status still distinguishes a draft from a repair/critic pass.
                await traceStore.append(AgentTraceEvent(phase: .draft, summary: "模型步骤 \(modelCalls)"), to: trace.id)
                let response: AgentModelResponse
                do {
                    response = try await complete(modelRequest, timeout: budget.timeoutSeconds - Date().timeIntervalSince(started))
                } catch {
                    degraded = true
                    if let runtimeError = error as? AgentRuntimeError, runtimeError == .timeout { timedOut = true }
                    await traceStore.append(AgentTraceEvent(phase: .failed, summary: "模型调用失败", success: false), to: trace.id)
                    if lastResponse.text == nil { lastResponse.text = "模型暂时不可用，以下只保留已核验的应用事实。" }
                    if !modelRetryUsed, !timedOut, modelCalls < budget.maxModelCalls {
                        modelRetryUsed = true
                        messages.append(AgentMessage(role: .system, content: "上一次模型调用未完成。仅重试一次，并继续使用已经读取的依据。"))
                        continue
                    }
                    break
                }
                lastResponse = response
                // Cancellation may arrive while the model call is in flight;
                // do not start parsing a new turn or any tool call afterwards.
                try checkBudgetAndCancellation()
                if response.toolCalls.isEmpty == false {
                    readRounds += 1
                    guard readRounds <= budget.maxReadRounds, toolCalls + response.toolCalls.count <= budget.maxToolCalls else {
                        degraded = true
                        status(.retrieve, "已达到读取上限")
                        break
                    }
                    status(.retrieve, "读取盘面和事件")
                    await traceStore.append(AgentTraceEvent(phase: .retrieve, summary: "读取第 \(readRounds) 轮"), to: trace.id)
                    for call in response.toolCalls {
                        try checkBudgetAndCancellation()
                        toolCalls += 1
                        do {
                            let result = try await readTool(call, timeout: budget.timeoutSeconds - Date().timeIntervalSince(started))
                            references.append(result)
                            messages.append(AgentMessage(role: .tool, content: renderPayload(result.payload), name: result.name.rawValue))
                            let evidenceClaim: String
                            switch result.name {
                            case .dayContext: evidenceClaim = "已读取选中日期的历法与盘面来源"
                            case .eventsContext: evidenceClaim = "已读取日期范围内的日程来源"
                            case .profileContext: evidenceClaim = "已读取出生档案来源"
                            case .chartContext: evidenceClaim = "已读取命盘来源"
                            case .notesContext: evidenceClaim = "已读取日笺或分析记录"
                            case .knowledgeSearch, .knowledgeRead: evidenceClaim = "已读取知识资料"
                            case .conversationContext: evidenceClaim = "已读取本轮会话上下文"
                            }
                            var record = EvidenceRecord(claim: evidenceClaim, sourceRef: result.sourceRef,
                                                         sourceRevision: result.sourceRevision, retrievedAt: result.retrievedAt,
                                                         evidenceType: result.evidenceType, loopStep: modelCalls)
                            let earlier = ledger.records(for: result.sourceRef)
                            let revisions = Set(earlier.map { $0.sourceRevision ?? "<unknown>" } + [result.sourceRevision ?? "<unknown>"])
                            if revisions.count > 1 { record.conflictSet = earlier.map(\.claimID); degraded = true }
                            ledger.append(record)
                            await traceStore.append(AgentTraceEvent(phase: .retrieve, summary: "读取 \(result.name.rawValue)", toolName: result.name, sourceRefs: [result.sourceRef]), to: trace.id)
                        } catch {
                            degraded = true
                            if let runtimeError = error as? AgentRuntimeError, runtimeError == .timeout { timedOut = true }
                            await traceStore.append(AgentTraceEvent(phase: .retrieve, summary: "读取失败", toolName: call.name, success: false), to: trace.id)
                            if timedOut { break }
                        }
                    }
                    if timedOut { break }
                    // A tool turn without text is not a final answer; ask the
                    // driver to use the typed results. A driver may combine a
                    // tool result and final text in one response, which can be
                    // accepted directly.
                    if !response.finished || response.text == nil { continue }
                }

                status(.deterministicCheck, "校验依据")
                let currentCritic = critique(response: response, references: references, skill: skill)
                critic = hasCompleteAnswer(response) ? currentCritic : merge(critic, currentCritic)
                if !critic.passed { degraded = true }
                let hasFactClaims = response.claims.contains { $0.evidenceType == .deterministicFact || $0.evidenceType == .knowledgeText }
                let checkSummary = !critic.passed ? "存在待核对依据" :
                    (hasFactClaims ? "结构化引用已通过校验" : "没有可评估的结构化事实声明")
                await traceStore.append(AgentTraceEvent(phase: .critic, summary: checkSummary, sourceRefs: ledger.records.map(\.sourceRef)), to: trace.id)
                if mode == .deep && !critic.passed && critic.needsSupplementalRead && !repairUsed && modelCalls < budget.maxModelCalls {
                    repairUsed = true
                    messages.append(AgentMessage(role: .system, content: "发现缺少或冲突的依据。只补读一次必要资料，保留已核验部分并标出不确定性。"))
                    degraded = true
                    continue
                }
                break
            }
            if modelCalls >= budget.maxModelCalls && !lastResponse.finished { degraded = true }
            try checkBudgetAndCancellation()
            status(.final, "整理结果", true)
        } catch let error as AgentRuntimeError {
            await traceStore.finish(trace.id, critic: critic, degraded: true, failure: error.localizedDescription)
            cancelled.remove(request.requestID)
            if case .cancelled = error { status(.cancelled, error.localizedDescription, true) }
            else { status(.failed, error.localizedDescription, true) }
            throw error
        } catch {
            degraded = true
            status(.failed, error.localizedDescription, true)
            await traceStore.finish(trace.id, critic: critic, degraded: true, failure: error.localizedDescription)
            cancelled.remove(request.requestID)
            throw AgentRuntimeError.unavailable(error.localizedDescription)
        }

        // A budget/timeout break can bypass the normal critique step. Assess
        // the actual final claims against raw reads again before binding them.
        let quality = AgentQualityReport.evaluate(claims: lastResponse.claims, references: references)
        let finalCritic = critique(response: lastResponse, references: references, skill: skill)
        // A repair may end with only a tool request when its budget runs out.
        // Such a response has not replaced the earlier answer or resolved its
        // issues. Only completed prose may replace the previous assessment;
        // a response that also carries tool calls and final prose still counts.
        critic = hasCompleteAnswer(lastResponse) ? finalCritic : merge(critic, finalCritic)
        if !critic.passed { degraded = true }
        for assessment in quality.claims where assessment.isCited {
            let claim = assessment.claim
            guard let match = references.last(where: {
                $0.sourceRef == claim.sourceRef && $0.sourceRevision == claim.sourceRevision &&
                    $0.evidenceType == claim.evidenceType
            }) else { continue }
            // Index-qualified identities keep duplicate model IDs from
            // suppressing a distinct claim or colliding with source records.
            let boundID = "\(request.requestID):claim:\(assessment.id)"
            ledger.append(EvidenceRecord(claimID: boundID, claim: claim.text, sourceRef: match.sourceRef,
                                         sourceRevision: match.sourceRevision, retrievedAt: match.retrievedAt,
                                         evidenceType: claim.evidenceType, confidence: claim.confidence,
                                         loopStep: modelCalls))
        }

        var uncertainty = critic.missingEvidence + critic.conflicts + critic.staleSources + critic.unsupportedClaims
        if uncertainty.isEmpty && degraded { uncertainty.append("部分模型或工具调用未完成，以上内容仅包含已返回的依据。") }
        let conclusion = lastResponse.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? lastResponse.text!
            : "已完成有限核验；请根据下方依据判断下一步。"
        let answer = AgentAnswer(conclusion: conclusion, evidence: ledger.records, interpretation: conclusion,
                                 actions: [], uncertainty: unique(uncertainty), mode: mode, degraded: degraded, critic: critic)
        await traceStore.finish(trace.id, critic: critic, degraded: degraded)
        cancelled.remove(request.requestID)
        return AgentRunResult(requestID: request.requestID, answer: answer, ledger: ledger, traceID: trace.id,
                              statuses: statuses, quality: quality)
    }

    private func inferredMode(_ text: String) -> AgentMode {
        let value = text.lowercased()
        return value.contains("严谨") || value.contains("核对") || value.contains("盘面") || value.contains("命盘") || value.contains("冲突") ? .deep : .quick
    }

    private func minimumBudget(_ current: AgentBudget, _ requested: AgentBudget) -> AgentBudget {
        AgentBudget(maxReadRounds: min(current.maxReadRounds, requested.maxReadRounds), maxToolCalls: min(current.maxToolCalls, requested.maxToolCalls), maxModelCalls: min(current.maxModelCalls, requested.maxModelCalls), timeoutSeconds: min(current.timeoutSeconds, requested.timeoutSeconds))
    }

    private func complete(_ request: AgentModelRequest, timeout: TimeInterval) async throws -> AgentModelResponse {
        guard timeout > 0 else { throw AgentRuntimeError.timeout }
        let driver = self.driver
        return try await withThrowingTaskGroup(of: AgentModelResponse.self) { group in
            group.addTask { try await driver.complete(request) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                throw AgentRuntimeError.timeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw AgentRuntimeError.timeout }
            return result
        }
    }

    private func readTool(_ call: AgentToolCall, timeout: TimeInterval) async throws -> AgentToolResult {
        guard timeout > 0 else { throw AgentRuntimeError.timeout }
        let tools = self.tools
        return try await withThrowingTaskGroup(of: AgentToolResult.self) { group in
            group.addTask { try await tools.read(call) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                throw AgentRuntimeError.timeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw AgentRuntimeError.timeout }
            return result
        }
    }

    private func hasCompleteAnswer(_ response: AgentModelResponse) -> Bool {
        response.finished && response.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func critique(response: AgentModelResponse, references: [AgentToolResult], skill: AgentSkill?) -> AgentCriticReport {
        var missing: [String] = [], stale: [String] = [], unsupported: [String] = [], conflicts: [String] = []
        let quality = AgentQualityReport.evaluate(claims: response.claims, references: references)
        for assessment in quality.claims {
            let claim = assessment.claim
            let source = claim.sourceRef ?? ""
            switch assessment.status {
            case .cited, .userInput: break
            case .modelInference:
                // Preserve the existing uncertainty signal for unsourced
                // inference without counting it as a factual citation failure.
                if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { unsupported.append(claim.text) }
            case .missingSource: unsupported.append(claim.text)
            case .sourceNotFound: missing.append("\(claim.text)（来源未读取）")
            case .missingRevision: missing.append("\(claim.text)（缺少声明版本）")
            case .sourceRevisionMissing: missing.append("\(source) 缺少来源版本")
            case .staleRevision: stale.append(source)
            case .typeMismatch: unsupported.append("\(claim.text)（来源类型不符）")
            case .conflictingRevisions: conflicts.append(source)
            }
        }
        // Conflicting reads remain visible even when the model emits no
        // structured claims and therefore has no measurable citation score.
        for (source, records) in Dictionary(grouping: references, by: \.sourceRef) {
            let versions = Set(records.map { record -> String? in
                guard let value = record.sourceRevision,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return value
            })
            if versions.count > 1 { conflicts.append(source) }
        }
        if let skill {
            let available = Set(references.map(\.name))
            let unread = skill.requiredTools.filter { tools.availableTools.contains($0) && !available.contains($0) }
            missing.append(contentsOf: unread.map { "Skill 要求读取 \($0.rawValue)" })
        }
        let failed = !missing.isEmpty || !stale.isEmpty || !unsupported.isEmpty || !conflicts.isEmpty
        let local = AgentCriticReport(passed: !failed, missingEvidence: unique(missing), conflicts: unique(conflicts),
                                      staleSources: unique(stale), unsupportedClaims: unique(unsupported), needsSupplementalRead: failed)
        return response.critic.map { merge(local, $0) } ?? local
    }

    private func merge(_ local: AgentCriticReport, _ model: AgentCriticReport) -> AgentCriticReport {
        let missing = unique(local.missingEvidence + model.missingEvidence)
        let conflicts = unique(local.conflicts + model.conflicts)
        let stale = unique(local.staleSources + model.staleSources)
        let unsupported = unique(local.unsupportedClaims + model.unsupportedClaims)
        let hasProblems = !missing.isEmpty || !conflicts.isEmpty || !stale.isEmpty || !unsupported.isEmpty
        return AgentCriticReport(passed: local.passed && model.passed && !hasProblems,
                                 missingEvidence: missing, conflicts: conflicts, staleSources: stale,
                                 unsupportedClaims: unsupported,
                                 needsSupplementalRead: local.needsSupplementalRead || model.needsSupplementalRead || hasProblems)
    }

    private func renderPayload(_ value: JSONValue) -> String {
        guard let data = try? AutomationJSON.encode(value) else { return "{}" }
        return String(String(decoding: data, as: UTF8.self).prefix(40_000))
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>(); return values.filter { seen.insert($0).inserted }
    }
}
