import Foundation
import Testing
import LingxiCore
import LingxiAgent
@testable import LingxiApp

/// Opt-in, paid-provider acceptance checks. The ordinary suite skips every
/// test unless the runner explicitly supplies a key in memory. No Keychain,
/// AppStore, user files or production calendar/profile data are accessed.
/// Each case permits exactly one AssistantService HTTP attempt, without retry.
@Suite(.serialized)
struct DeepSeekLiveAcceptanceTests {
    private static var liveEnabled: Bool {
        !(ProcessInfo.processInfo.environment["LINGXI_DEEPSEEK_LIVE_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private struct Credentials: Sendable {
        let key: String
        let model: String

        static func load() throws -> Credentials {
            guard let key = ProcessInfo.processInfo.environment["LINGXI_DEEPSEEK_LIVE_KEY"],
                  !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AcceptanceError.missingExplicitCredential
            }
            let model = ProcessInfo.processInfo.environment["LINGXI_DEEPSEEK_LIVE_MODEL"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Credentials(key: key, model: model?.isEmpty == false ? model! : "deepseek-flash")
        }
    }

    private enum AcceptanceError: Error {
        case missingExplicitCredential, requestLimitExceeded, reportWriteFailed
    }

    private actor Recorder {
        private(set) var httpAttempts = 0
        private(set) var reply: AgentModelResponse?
        private(set) var structuredConclusion: String?
        private(set) var transportStatus = "not_called"

        func begin() throws {
            guard httpAttempts == 0 else { throw AcceptanceError.requestLimitExceeded }
            httpAttempts += 1
            transportStatus = "started"
        }

        func received(_ decoded: AgentModelResponse, raw: String) {
            reply = decoded
            // Never log the codec's plain-text fallback: it may contain an
            // entire malformed envelope, including fields we did not request.
            if let first = raw.firstIndex(of: "{"), let last = raw.lastIndex(of: "}"), first <= last,
               let data = String(raw[first...last]).data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                structuredConclusion = object["conclusion"] as? String
            }
            transportStatus = "response_received"
        }

        func failed(_ error: Error) {
            switch error {
            case AssistantService.ServiceError.http(let code): transportStatus = "http_\(code)"
            case AssistantService.ServiceError.badResponse: transportStatus = "invalid_response"
            case AssistantService.ServiceError.invalidConfiguration: transportStatus = "invalid_configuration"
            case is CancellationError: transportStatus = "cancelled"
            default: transportStatus = "transport_or_decode_error"
            }
        }

        func observation() -> (Int, AgentModelResponse?, String?, String) {
            (httpAttempts, reply, structuredConclusion, transportStatus)
        }
    }

    private struct Observation {
        let result: AgentRunResult?
        let reply: AgentModelResponse?
        let conclusion: String?
        let httpAttempts: Int
        let transportStatus: String
        let duration: TimeInterval
        let inspectionRecorded: Bool
    }

    private actor Drafts {
        private var values: [AgentConfigDocument: String]
        init(_ values: [AgentConfigDocument: String]) { self.values = values }
        func snapshot() -> AgentConfigurationSnapshot { AgentConfigurationSnapshot(values: values) }
        func replace(_ newValues: [AgentConfigDocument: String]) { values = newValues }
    }

    private static func run(
        id: String, text: String, credentials: Credentials,
        snapshot: AgentConfigurationSnapshot = AgentConfigurationSnapshot(values: [:]),
        reference: AgentToolResult? = nil,
        referenceArguments: [String: JSONValue] = [:],
        beforeHTTP: @escaping @Sendable (AgentModelRequest) async -> Void = { _ in }
    ) async -> Observation {
        let recorder = Recorder()
        let started = Date()
        let gateway = ClosureModelGateway { request in
            // Match the app's deterministic first read. This is local; only
            // the subsequent call below reaches the real model provider.
            if request.step == 1, let reference {
                return AgentModelResponse(toolCalls: [AgentToolCall(name: reference.name, arguments: referenceArguments)], finished: false)
            }
            try await recorder.begin()
            await beforeHTTP(request)
            do {
                let raw = try await AssistantService.reply(
                    endpoint: "https://api.deepseek.com/chat/completions", model: credentials.model,
                    key: credentials.key, messages: [], context: "本次仅使用固定合成验收资料。",
                    structuredAgent: true, agentContext: request.context, agentMessages: request.messages
                )
                let decoded = AgentResponseCodec.decode(raw)
                await recorder.received(decoded, raw: raw)
                return decoded
            } catch {
                await recorder.failed(error)
                throw error
            }
        }
        var handlers: [AgentToolName: TypedToolRegistry.Handler] = [:]
        if let reference {
            handlers[reference.name] = { call in
                var result = reference
                result.callID = call.id
                return result
            }
        }
        var skill = snapshot.chatSkill(includeSystemData: false)
        skill.requiredTools = reference.map { [$0.name] } ?? []
        let runtime = AgentRuntime(driver: gateway, tools: TypedToolRegistry(handlers: handlers),
                                   skillRegistry: SkillRegistry(skills: [skill]),
                                   contextBuilder: PromptContextBuilder(configuration: snapshot.configuration),
                                   budget: AgentBudget(maxReadRounds: 1, maxToolCalls: 1,
                                                       maxModelCalls: reference == nil ? 1 : 2, timeoutSeconds: 30),
                                   modelName: credentials.model)
        let result: AgentRunResult?
        do { result = try await runtime.run(AgentRequest(requestID: id, text: text, mode: .deep)) }
        catch { result = nil } // Report only the allowlisted transport status.
        var inspectionRecorded = false
        if let result {
            let trace = await runtime.trace(result.traceID)
            let model = credentials.model
            inspectionRecorded = await MainActor.run {
                let store = AgentQualityStore()
                store.record(requestID: id, result: result, trace: trace, model: model)
                guard let record = store.records.first, let recorded = record.result,
                      let recordedTrace = record.trace, let endedAt = recordedTrace.endedAt,
                      let duration = recordedTrace.duration else { return false }
                return store.records.count == 1 && record.id == id && record.model == model &&
                    record.failure == nil && recordedTrace.id == result.traceID && recordedTrace == trace &&
                    recordedTrace.model == model && recordedTrace.requestID == id &&
                    recordedTrace.modelCalls == (reference == nil ? 1 : 2) &&
                    recordedTrace.startedAt.timeIntervalSince1970.isFinite && endedAt >= recordedTrace.startedAt &&
                    duration.isFinite && duration >= 0 &&
                    recorded.quality == result.quality && recorded.ledger.records == result.ledger.records &&
                    recorded.answer.evidence == result.answer.evidence && recorded.answer.conclusion == result.answer.conclusion
            }
        }
        let captured = await recorder.observation()
        return Observation(result: result, reply: captured.1, conclusion: captured.2,
                           httpAttempts: captured.0, transportStatus: captured.3,
                           duration: max(0, Date().timeIntervalSince(started)), inspectionRecorded: inspectionRecorded)
    }

    @Test(.enabled(if: DeepSeekLiveAcceptanceTests.liveEnabled))
    func liveDeterministicDateUsesExactSourceRevision() async throws {
        let credentials = try Credentials.load()
        let engine = CalendarEngine()
        let instant = try #require(engine.gregorian.date(from: DateComponents(year: 2010, month: 3, day: 15, hour: 12)))
        let civilDay = engine.gregorian.startOfDay(for: instant)
        let flow = try FourPillarsEngine().chart(at: instant, timeZone: CalendarEngine.timeZone, dayBoundary: .midnight)
        let payload = JSONValue.object([
            "date": .string("2010-03-15"), "referenceTime": .string("12:00"),
            "timeZone": .string(CalendarEngine.timeZone.identifier),
            "flowChart": AutomationFacts.chart(flow),
            "almanac": AutomationFacts.almanac(try AlmanacEngine.shared.day(on: civilDay)),
            "festivals": .array(engine.festivals(on: civilDay).map { festival in
                .object(["name": .string(festival.name), "summary": .string(festival.summary),
                         "region": .string(festival.region), "sourceTitle": .string(festival.sourceTitle),
                         "sourceURL": .string(festival.sourceURL)])
            })
        ])
        // Assemble calendar.day's public DTO from the real engines, then use
        // the application's pure cloud mapping/projection. No Router or
        // AppStore is constructed, so this never opens private data stores.
        let call = AgentToolCall(id: "live-calendar-read", name: .dayContext,
                                 arguments: ["date": .string("2010-03-15"), "at": .string("12:00")])
        let request = try AppAutomationToolProvider.request(for: call, cloudOnly: true)
        let reference = try AppAutomationToolProvider.result(for: call, request: request, payload: payload, cloudOnly: true)
        let source = reference.sourceRef
        let revision = try #require(reference.sourceRevision)
        let projectionRevision = try AutomationSnapshot.revision(reference.payload)
        let observation = await Self.run(id: "live-date-revision", text: """
        请只使用已经读取的日期依据，回答 2010-03-15 的日干支是什么。
        返回 JSON，conclusion 用 YYYY-MM-DD 格式写出日期及日干支；claims 恰好一条，evidenceType 为 deterministicFact，
        sourceRef 和 sourceRevision 必须逐字复制已读取的依据。不要返回新工具调用或其他事实。
        """, credentials: credentials, reference: reference, referenceArguments: call.arguments)
        let claims = observation.reply?.claims ?? []
        let checks: [String: Bool] = [
            "one_http_attempt": observation.httpAttempts == 1,
            "structured_response": observation.conclusion != nil,
            "known_engine_anchor": flow.day.text == "甲子",
            "public_cloud_projection_bound": request.method == "calendar.day" && source.hasPrefix("automation:calendar.day:") &&
                revision == projectionRevision && reference.payload["flowChart"]?["pillars"]?["day"]?["pillar"]?["text"]?.stringValue == "甲子",
            "correct_conclusion": observation.conclusion?.contains("2010-03-15") == true && observation.conclusion?.contains("甲子") == true,
            "one_exact_fact_claim": claims.count == 1 && claims.first?.evidenceType == .deterministicFact &&
                claims.first?.sourceRef == source && claims.first?.sourceRevision == revision && claims.first?.text.contains("甲子") == true,
            "fully_cited": observation.result?.quality?.factClaimCount == 1 && observation.result?.quality?.citedFactCount == 1 &&
                observation.result?.quality?.citationCoverage == 1,
            "runtime_passed": observation.result?.answer.critic.passed == true && observation.result?.answer.degraded == false,
            "quality_panel_receipt_recorded": observation.inspectionRecorded,
            "no_further_tools": observation.reply?.toolCalls.isEmpty == true
        ]
        try Self.report(id: "date-revision", observation: observation, credentials: credentials, checks: checks)
        #expect(checks.values.allSatisfy { $0 }, "真实日期与版本引用验收未全部通过；详见脱敏案例报告。")
    }

    @Test(.enabled(if: DeepSeekLiveAcceptanceTests.liveEnabled))
    func liveMissingBirthDataProducesNoChartClaims() async throws {
        let credentials = try Credentials.load()
        let observation = await Self.run(id: "live-missing-birth", text: """
        我想看出生四柱，但还没有提供任何出生日期、时刻或地点，应用也没有读取任何出生档案。
        请按实际可用资料回答。若缺资料，请在 JSON 的 conclusion 中包含短标记 NEED_BIRTH_DATA，
        说明还需要的资料；不要猜测出生日期、天干地支或命盘，也不要调用工具。
        同时说明本应用的时间计算口径，并如实说明是否支持真太阳时校正。
        没有可核对的盘面事实时 claims 必须是空数组。不要输出思维链。
        """, credentials: credentials)
        let conclusion = observation.conclusion ?? ""
        let containsPillar = conclusion.range(of: "[甲乙丙丁戊己庚辛壬癸][子丑寅卯辰巳午未申酉戌亥]", options: .regularExpression) != nil
        let checks: [String: Bool] = [
            "one_http_attempt": observation.httpAttempts == 1,
            "structured_response": observation.conclusion != nil,
            "missing_data_marker": conclusion.contains("NEED_BIRTH_DATA"),
            "requests_birth_information": conclusion.contains("出生") && (conclusion.contains("日期") || conclusion.contains("年月日")) &&
                (conclusion.contains("时") || conclusion.contains("时间")),
            "no_fabricated_pillars": !containsPillar,
            "accurate_supported_time_basis": conclusion.contains("民用时区") &&
                ["不支持真太阳时", "未支持真太阳时", "不提供真太阳时", "不进行真太阳时", "不做真太阳时"].contains { conclusion.contains($0) },
            "no_chart_claims": observation.reply?.claims.isEmpty == true,
            "no_tool_requests": observation.reply?.toolCalls.isEmpty == true,
            "no_invented_coverage": observation.result?.quality?.factClaimCount == 0 && observation.result?.quality?.citationCoverage == nil,
            "runtime_completed": observation.result != nil && observation.result?.answer.degraded == false,
            "quality_panel_receipt_recorded": observation.inspectionRecorded
        ]
        try Self.report(id: "missing-birth", observation: observation, credentials: credentials, checks: checks)
        #expect(checks.values.allSatisfy { $0 }, "真实缺资料验收未全部通过；详见脱敏案例报告。")
    }

    @Test(.enabled(if: DeepSeekLiveAcceptanceTests.liveEnabled))
    func liveConfigurationSnapshotKeepsOriginalMarker() async throws {
        let credentials = try Credentials.load()
        let original: [AgentConfigDocument: String] = [
            .soul: "你是提供简短回答的合成测试伙伴。",
            .agent: "本轮短标记为 FREEZE-A7。收到配置验收请求时，conclusion 必须且仅为‘合成访客甲｜FREEZE-A7’；claims 为 []。",
            .user: "本轮请称呼我为合成访客甲。",
            .skill: "本轮只检查称呼和短标记，不提供盘面或历法解读，不请求工具。"
        ]
        let changed: [AgentConfigDocument: String] = [
            .soul: "已经更新的合成测试伙伴。", .agent: "新的短标记为 FREEZE-B9。",
            .user: "新的称呼为合成访客乙。", .skill: "更新后的任务方法。"
        ]
        let drafts = Drafts(original)
        let frozen = await drafts.snapshot()
        let observation = await Self.run(id: "live-frozen-configuration",
                                         text: "这是配置验收请求。请仅按本轮生效配置输出称呼和短标记，使用 JSON；claims 为 []，不调用工具。",
                                         credentials: credentials, snapshot: frozen, beforeHTTP: { _ in
            // Change the backing drafts after runtime context construction but
            // before the actual HTTP request; that request must retain frozen.
            await drafts.replace(changed)
        })
        let latest = await drafts.snapshot()
        let conclusion = observation.conclusion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let checks: [String: Bool] = [
            "one_http_attempt": observation.httpAttempts == 1,
            "structured_response": observation.conclusion != nil,
            "drafts_changed_during_run": latest.values == AgentConfigurationSnapshot(values: changed).values,
            "original_snapshot_retained": frozen.values == AgentConfigurationSnapshot(values: original).values,
            "exact_original_name_and_marker": conclusion == "合成访客甲｜FREEZE-A7",
            "no_new_marker": conclusion?.contains("FREEZE-B9") == false && conclusion?.contains("合成访客乙") == false,
            "no_fact_claims": observation.reply?.claims.isEmpty == true,
            "no_tool_requests": observation.reply?.toolCalls.isEmpty == true,
            "runtime_completed": observation.result != nil && observation.result?.answer.degraded == false,
            "quality_panel_receipt_recorded": observation.inspectionRecorded
        ]
        try Self.report(id: "frozen-configuration", observation: observation, credentials: credentials, checks: checks)
        #expect(checks.values.allSatisfy { $0 }, "真实配置快照验收未全部通过；详见脱敏案例报告。")
    }

    private struct ClaimReport: Codable {
        let text: String
        let evidenceType: String
        let sourceRef: String?
        let sourceRevision: String?
        let status: String
    }

    private struct CaseReport: Codable {
        let caseID: String
        let model: String
        let passed: Bool
        let checks: [String: Bool]
        let conclusion: String
        let claims: [ClaimReport]
        let factClaimCount: Int?
        let citedFactCount: Int?
        let citationCoverage: Double?
        let criticPassed: Bool?
        let degraded: Bool?
        let httpAttempts: Int
        let transportStatus: String
        let durationSeconds: TimeInterval
        let scope: String
    }

    private static func sanitize(_ text: String, credential: String, limit: Int = 800) -> String {
        var value = text.replacingOccurrences(of: credential, with: "[REDACTED]")
        value = value.replacingOccurrences(of: "(?is)<think>.*?(?:</think>|$)", with: "[omitted]", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?i)(?:bearer\\s+\\S+|sk-[A-Za-z0-9_-]{6,})", with: "[REDACTED]", options: .regularExpression)
        return String(value.prefix(limit))
    }

    private static func report(id: String, observation: Observation, credentials: Credentials, checks: [String: Bool]) throws {
        let quality = observation.result?.quality
        let claims = (observation.reply?.claims ?? []).prefix(8).enumerated().map { index, claim in
            ClaimReport(text: sanitize(claim.text, credential: credentials.key, limit: 400),
                        evidenceType: claim.evidenceType.rawValue,
                        sourceRef: claim.sourceRef.map { sanitize($0, credential: credentials.key, limit: 256) },
                        sourceRevision: claim.sourceRevision.map { sanitize($0, credential: credentials.key, limit: 128) },
                        status: quality?.claims.indices.contains(index) == true ? quality!.claims[index].status.rawValue : "未完成运行时评估")
        }
        let safeConclusion = sanitize(observation.conclusion ?? "未返回可识别的 JSON 结论（原始内容未记录）", credential: credentials.key)
        let record = CaseReport(caseID: id, model: sanitize(credentials.model, credential: credentials.key, limit: 80),
                                passed: checks.values.allSatisfy { $0 }, checks: checks, conclusion: safeConclusion,
                                claims: claims, factClaimCount: quality?.factClaimCount, citedFactCount: quality?.citedFactCount,
                                citationCoverage: quality?.citationCoverage, criticPassed: observation.result?.answer.critic.passed,
                                degraded: observation.result?.answer.degraded, httpAttempts: observation.httpAttempts,
                                transportStatus: observation.transportStatus, durationSeconds: observation.duration,
                                scope: "一次真实模型请求；固定合成资料；日期案例使用公开领域引擎 DTO 与应用云端投影；验证应用传输、编解码、运行时及质量面板 Store 数据绑定，不读取私有资料，不代表广泛语义准确率或 Router/UI 端到端测试。")
        print("DeepSeek live \(id): \(record.passed ? "PASS" : "FAIL"), HTTP \(record.httpAttempts), \(String(format: "%.2f", record.durationSeconds))s, claims \(record.claims.map(\.status).joined(separator: ",")), conclusion=\(safeConclusion)")
        guard let path = ProcessInfo.processInfo.environment["LINGXI_DEEPSEEK_REPORT_DIR"], !path.isEmpty else { return }
        guard path.hasPrefix("/") else { throw AcceptanceError.reportWriteFailed }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(record).write(to: directory.appendingPathComponent("deepseek-live-\(id).json"), options: .atomic)
        } catch { throw AcceptanceError.reportWriteFailed }
    }
}
