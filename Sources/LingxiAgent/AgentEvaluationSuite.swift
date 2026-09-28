import Foundation
import LingxiCore

public enum AgentEvaluationCategory: String, CaseIterable, Identifiable, Sendable {
    case facts = "事实问答"
    case chartKnowledge = "盘面与知识"
    case missingData = "缺少资料"
    case conflicts = "冲突资料"
    case localWrites = "本地写入"
    case repeatedRequests = "重复请求"
    case cancellationTimeout = "取消与超时"
    public var id: String { rawValue }
}

public struct AgentEvaluationCaseResult: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: AgentEvaluationCategory
    public let passed: Bool
    public let detail: String
    public let duration: TimeInterval

    public init(id: String, title: String, category: AgentEvaluationCategory, passed: Bool,
                detail: String, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.category = category
        self.passed = passed
        self.detail = detail
        self.duration = duration
    }
}

public struct AgentEvaluationReport: Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let results: [AgentEvaluationCaseResult]
    public let cancelled: Bool
    public var passedCount: Int { results.filter(\.passed).count }
    public var totalCount: Int { results.count }
    public var failedCount: Int { results.filter { !$0.passed }.count }

    public init(startedAt: Date, endedAt: Date, results: [AgentEvaluationCaseResult], cancelled: Bool) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.results = results
        self.cancelled = cancelled
    }
}

/// Fixed synthetic component regressions, never a live-model accuracy score.
/// No network gateway, AppAutomationRouter, UI, user files or system calendars
/// participate. Scripted model replies exercise the real runtime and quality
/// checks; local writes combine the real journal and isolated domain stores.
public enum AgentEvaluationSuite {
    public static let caseCount = 41

    private struct Check: Sendable {
        let id: String
        let title: String
        let category: AgentEvaluationCategory
        let body: @Sendable () async throws -> String
    }

    private struct Failure: Error { let detail: String }

    public static func run() async -> AgentEvaluationReport {
        let started = Date()
        var results: [AgentEvaluationCaseResult] = []
        let checks = factChecks + chartChecks + missingChecks + conflictChecks + writeChecks + replayChecks + interruptionChecks
        for check in checks {
            await Task.yield()
            if Task.isCancelled { break }
            let beginning = Date()
            let passed: Bool
            let detail: String
            do {
                detail = try await check.body()
                passed = true
            } catch let failure as Failure {
                detail = failure.detail
                passed = false
            } catch {
                // Never surface arbitrary gateway output or filesystem paths.
                detail = "组件抛出未预期错误（\(String(describing: type(of: error)))）；仅使用合成资料。"
                passed = false
            }
            if Task.isCancelled { break }
            results.append(AgentEvaluationCaseResult(id: check.id, title: check.title, category: check.category,
                                                      passed: passed, detail: detail,
                                                      duration: max(0, Date().timeIntervalSince(beginning))))
        }
        return AgentEvaluationReport(startedAt: started, endedAt: Date(), results: results, cancelled: Task.isCancelled)
    }

    private static func require(_ condition: Bool, _ detail: String) throws {
        guard condition else { throw Failure(detail: detail) }
    }

    private static func date(_ text: String) throws -> Date {
        guard let value = ISO8601DateFormatter().date(from: text) else { throw Failure(detail: "固定样例日期无效。") }
        return value
    }

    private static func value<T: Encodable>(_ model: T) throws -> JSONValue {
        try AutomationJSON.decode(JSONValue.self, from: AutomationJSON.encode(model))
    }

    private static func proof(_ id: String, _ title: String, _ category: AgentEvaluationCategory,
                              _ detail: String, tool: AgentToolName = .dayContext,
                              evidenceType: EvidenceType = .deterministicFact,
                              fixture: @escaping @Sendable () throws -> JSONValue) -> Check {
        Check(id: id, title: title, category: category) {
            let payload = try fixture()
            let revision = try AutomationSnapshot.revision(payload)
            let source = "synthetic:" + id
            let claim = AgentClaim(text: title, sourceRef: source, sourceRevision: revision,
                                   evidenceType: evidenceType, confidence: 1)
            let runtime = makeRuntime(tool: tool, payload: payload, source: source, revision: revision,
                                      evidenceType: evidenceType, claim: claim)
            let result = try await runtime.run(AgentRequest(requestID: id, text: title, mode: .deep))
            try require(result.answer.critic.passed && !result.answer.degraded, "固定事实或引用未通过运行时复核。")
            try require(result.quality?.factClaimCount == 1 && result.quality?.citedFactCount == 1 &&
                        result.quality?.citationCoverage == 1, "固定事实未得到完整的来源与版本绑定。")
            let trace = await runtime.trace(result.traceID)
            try require(trace?.modelCalls == 2 && trace?.toolCalls == 1, "实际运行时没有完成预期的读取与复核轮次。")
            return detail + "；真实运行时读取后复核，引用 1/1。合成组件检查。"
        }
    }

    private static func makeRuntime(tool: AgentToolName, payload: JSONValue, source: String = "synthetic:source",
                                    revision: String? = "r1", evidenceType: EvidenceType = .deterministicFact,
                                    claim: AgentClaim) -> AgentRuntime {
        let gateway = ClosureModelGateway { request in
            if request.step == 1 { return AgentModelResponse(toolCalls: [AgentToolCall(name: tool)], finished: false) }
            return AgentModelResponse(text: "合成答复", claims: [claim])
        }
        let tools = TypedToolRegistry(handlers: [tool: { call in
            AgentToolResult(callID: call.id, name: tool, payload: payload, sourceRef: source,
                            sourceRevision: revision, evidenceType: evidenceType)
        }])
        return AgentRuntime(driver: gateway, tools: tools,
                            skillRegistry: SkillRegistry(skills: [AgentSkill(id: "synthetic", title: "合成回归", requiredTools: [tool])]))
    }

    private static var factChecks: [Check] { [
        proof("fact.lunar-new-year", "春节的农历日期", .facts, "2026 春节对应正月初一") {
            let info = CalendarEngine().info(for: try date("2026-02-17T04:00:00Z"))
            try require(info.lunarDate == "正月初一", "春节农历日期偏离固定预期。")
            return .string(info.lunarDate)
        },
        proof("fact.mid-autumn", "中秋的日期与目录", .facts, "2026 中秋为八月十五且命中中秋目录") {
            let day = try date("2026-09-25T04:00:00Z"), engine = CalendarEngine()
            try require(engine.info(for: day).lunarDate == "八月十五" && engine.festivals(on: day).contains { $0.id == "mid-autumn" }, "中秋日期或节日匹配失败。")
            return .string(engine.festivals(on: day).map(\.name).joined(separator: "、"))
        },
        proof("fact.leap-observance", "闰月不重复普通月纪念日", .facts, "闰六月十九保留闰月标记且不重复观音成道日") {
            let day = try date("2025-08-12T04:00:00Z"), engine = CalendarEngine()
            try require(engine.info(for: day).lunarDate == "闰六月十九" && engine.festivals(on: day).isEmpty, "闰月纪念日规则回归。")
            return .string(engine.info(for: day).lunarDate)
        },
        proof("fact.civil-year", "民用干支年在春节换年", .facts, "立春后春节前仍为乙巳，春节起为丙午") {
            let engine = CalendarEngine()
            let before = engine.info(for: try date("2026-02-04T04:00:00Z")).yearGanZhi
            let after = engine.info(for: try date("2026-02-17T04:00:00Z")).yearGanZhi
            try require(before == "乙巳" && after == "丙午", "民用干支年与立春年混淆。")
            return .array([.string(before), .string(after)])
        },
        proof("fact.day-anchor", "日干支的固定历书锚点", .facts, "2010-03-15 为甲子日") {
            let text = CalendarEngine().dayGanZhi(for: try date("2010-03-15T04:00:00Z"))
            try require(text == "甲子", "日干支锚点发生偏移。")
            return .string(text)
        },
        proof("fact.beijing-midnight", "UTC 输入跨北京时间零点", .facts, "UTC 16 点对应春节民用日边界") {
            let engine = CalendarEngine()
            let a = engine.info(for: try date("2026-02-16T15:59:59Z")).lunarDate
            let b = engine.info(for: try date("2026-02-16T16:00:00Z")).lunarDate
            try require(a == "腊月廿九" && b == "正月初一", "时区转换后的民用日边界错误。")
            return .array([.string(a), .string(b)])
        },
        proof("fact.qingming-dates", "清明不是固定公历日", .facts, "2025 清明为4月4日，2026 为4月5日") {
            let engine = CalendarEngine()
            try require(engine.solarTerm(on: date("2025-04-04T04:00:00Z")) == "清明" && engine.solarTerm(on: date("2026-04-05T04:00:00Z")) == "清明", "年度节气日期错误。")
            return .array([.string("2025-04-04"), .string("2026-04-05")])
        },
        proof("fact.solar-boundary", "节气精确交界的前后归属", .facts, "交节瞬间属于新节气，下一节气严格在后") {
            let engine = CalendarEngine()
            guard let term = try engine.solarTerms(in: 2026).first(where: { $0.name == "秋分" }) else { throw Failure(detail: "固定节气缺失。") }
            let before = try engine.solarTermContext(at: term.date.addingTimeInterval(-0.1))
            let exact = try engine.solarTermContext(at: term.date)
            try require(before.next == term && exact.previous == term && exact.next.date > term.date, "节气交界归属错误。")
            return .string(exact.previous.name)
        },
        proof("fact.month-grid", "月历日期连续且从周一开始", .facts, "2026年9月月历含42个连续日期，首日为8月31日") {
            let engine = CalendarEngine(), days = CalendarEngine().monthDays(containing: try date("2026-09-17T04:00:00Z"))
            try require(days.count == 42 && Set(days).count == 42 && days.first == date("2026-08-30T16:00:00Z"), "月历网格日期不完整。")
            try require(zip(days, days.dropFirst()).allSatisfy { engine.gregorian.dateComponents([.day], from: $0, to: $1).day == 1 }, "月历网格日期不连续。")
            return .number(Double(days.count))
        },
        proof("fact.catalog-sources", "节日目录保留来源与地域", .facts, "节日ID唯一，每条保留HTTPS来源与地域") {
            let rows = FestivalCatalog.all
            try require(!rows.isEmpty && Set(rows.map(\.id)).count == rows.count && rows.allSatisfy { !$0.region.isEmpty && !$0.sourceTitle.isEmpty && URL(string: $0.sourceURL)?.scheme == "https" }, "节日目录缺少独立来源或稳定标识。")
            return .array(rows.map { .object(["id": .string($0.id), "source": .string($0.sourceURL)]) })
        }
    ] }

    private static var chartChecks: [Check] { [
        proof("chart.known-pillars", "已知时刻的四柱基准", .chartKnowledge, "2005-12-23 08:37 四柱匹配固定基准", tool: .chartContext) {
            let profile = BirthProfile(birthYear: 2005, birthMonth: 12, birthDay: 23, birthHour: 8, birthMinute: 37, birthTimeKnown: true)
            let charts = try FourPillarsEngine().natalCharts(for: profile)
            guard let chart = charts.first else { throw Failure(detail: "未生成命盘。") }
            try require(charts.count == 1 && [chart.year.text, chart.month.text, chart.day.text, chart.hour?.text] == ["乙酉", "戊子", "辛巳", "壬辰"], "已知时刻四柱偏离基准。")
            return AutomationFacts.chart(chart)
        },
        proof("chart.lichun", "立春瞬间同时切换年柱月柱", .chartKnowledge, "乙巳己丑切换为丙午庚寅", tool: .chartContext) {
            let engine = FourPillarsEngine()
            guard let term = try engine.solarTerms(in: 2026).first(where: { $0.name == "立春" }) else { throw Failure(detail: "立春边界缺失。") }
            let before = try engine.chart(at: term.date.addingTimeInterval(-1)), after = try engine.chart(at: term.date)
            try require([before.year.text, before.month.text, after.year.text, after.month.text] == ["乙巳", "己丑", "丙午", "庚寅"], "立春换柱错误。")
            return .array([AutomationFacts.chart(before), AutomationFacts.chart(after)])
        },
        proof("chart.monthly-jie", "白露按精确时刻切换月柱", .chartKnowledge, "白露前丙申，交节后丁酉", tool: .chartContext) {
            let engine = FourPillarsEngine()
            guard let term = try engine.solarTerms(in: 2026).first(where: { $0.name == "白露" }) else { throw Failure(detail: "白露边界缺失。") }
            let before = try engine.chart(at: term.date.addingTimeInterval(-1)), after = try engine.chart(at: term.date)
            try require(before.month.text == "丙申" && after.month.text == "丁酉", "十二节的换月边界错误。")
            return .array([.string(before.month.text), .string(after.month.text)])
        },
        proof("chart.qi-keeps-month", "秋分中气不切换月柱", .chartKnowledge, "中气前后保持同一月柱", tool: .chartContext) {
            let engine = FourPillarsEngine()
            guard let term = try engine.solarTerms(in: 2026).first(where: { $0.name == "秋分" }) else { throw Failure(detail: "秋分边界缺失。") }
            let a = try engine.chart(at: term.date.addingTimeInterval(-1)), b = try engine.chart(at: term.date)
            try require(a.month == b.month, "中气被错误用于换月。")
            return .string(b.month.text)
        },
        proof("chart.day-boundary", "零点与晚子时口径分别保留", .chartKnowledge, "两种日界日柱不同，晚子时时柱一致", tool: .chartContext) {
            let engine = FourPillarsEngine(), instant = try date("1988-02-15T23:30:00+08:00")
            let a = try engine.chart(at: instant, dayBoundary: .midnight), b = try engine.chart(at: instant, dayBoundary: .ziHour23)
            try require(a.day.text == "庚子" && b.day.text == "辛丑" && a.hour == b.hour, "日界选项没有保留各自口径。")
            return .array([.string(a.day.text), .string(b.day.text)])
        },
        proof("knowledge.rule-provenance", "传统解释携带规则来源", .chartKnowledge, "黄历资料标记传统规则并附规则来源", tool: .knowledgeRead, evidenceType: .knowledgeText) {
            let exported = AutomationFacts.almanac(try AlmanacEngine.shared.day(on: date("2026-09-17T04:00:00Z")))
            try require(exported["classification"]?.stringValue == "traditionalRules" && exported["sourceURL"]?.stringValue == AlmanacEngine.sourceURL, "传统分类丢失来源或被当成预测。")
            return .object(["classification": exported["classification"] ?? .null, "source": exported["sourceURL"] ?? .null, "boundary": exported["boundaryNote"] ?? .null])
        },
        proof("chart.luck-handover", "大运按交运时刻连续衔接", .chartKnowledge, "十步大运首尾相接，首运从实际交运时刻开始", tool: .chartContext) {
            let profile = BirthProfile(birthYear: 1990, birthMonth: 8, birthDay: 12, birthHour: 9, birthMinute: 30, birthTimeKnown: true)
            let chart = try LuckCycleEngine().calculate(for: profile, gender: .female)
            try require(chart.cycles.count == 10 && chart.cycles.first?.start == chart.startAt && zip(chart.cycles, chart.cycles.dropFirst()).allSatisfy { $0.end == $1.start }, "大运时段存在缺口或错误起点。")
            return AutomationFacts.luck(chart)
        },
        proof("chart.flow-months", "流年按十二节分成十二流月", .chartKnowledge, "十二流月覆盖整段立春流年且无缺口", tool: .chartContext) {
            let engine = LuckCycleEngine(), year = try LuckCycleEngine().flowYear(2026)
            let months = try engine.flowMonths(in: year)
            try require(months.count == 12 && months.first?.start == year.start && months.last?.end == year.end && zip(months, months.dropFirst()).allSatisfy { $0.end == $1.start }, "流月划分未覆盖完整流年。")
            return AutomationFacts.flowYear(year, months: months)
        },
        proof("chart.almanac-hours", "黄历包含早晚子时十三时段", .chartKnowledge, "十三时段覆盖民用日，九星保留九宫", tool: .dayContext) {
            let exported = AutomationFacts.almanac(try AlmanacEngine.shared.day(on: date("2026-09-17T04:00:00Z")))
            try require(exported["hours"]?.arrayValue?.count == 13 && exported["hours"]?.arrayValue?.first?["label"]?.stringValue == "早子时" && exported["hours"]?.arrayValue?.last?["endMinute"]?.intValue == 1440 && exported["dayNineStar"]?["palaces"]?.arrayValue?.count == 9, "日黄历时段或九宫数据不完整。")
            return .object(["hours": .number(13), "first": exported["hours"]?.arrayValue?.first ?? .null, "last": exported["hours"]?.arrayValue?.last ?? .null])
        },
        proof("knowledge.reading-boundary", "日运解释保留假设和不确定性", .chartKnowledge, "未指定旺衰保持未确定，未知时柱不补造", tool: .chartContext) {
            let engine = FourPillarsEngine()
            let natal = try engine.chart(at: date("1990-08-12T01:30:00Z"), includeHour: false)
            let flow = try engine.chart(at: date("2026-09-17T04:00:00Z"))
            let exported = AutomationFacts.reading(try PersonalDailyReadingEngine().analyze(natal: natal, flow: flow))
            try require(exported["strength"]?.stringValue == "unspecified" && exported["hasUnknownBirthHour"]?.boolValue == true && exported["periods"]?.arrayValue?.count == 3, "日运解释擅自确定旺衰或时柱。")
            return .object(["strength": exported["strength"] ?? .null, "unknownHour": exported["hasUnknownBirthHour"] ?? .null, "scope": exported["scopeNote"] ?? .null])
        }
    ] }

    private static var missingChecks: [Check] { [
        proof("missing.birth-hour", "出生时刻未知时不生成时柱", .missingData, "未知时刻只导出三个已知柱", tool: .profileContext) {
            guard let chart = try FourPillarsEngine().natalCharts(for: BirthProfile(birthYear: 1990, birthMonth: 1, birthDay: 15)).first else { throw Failure(detail: "合成命盘缺失。") }
            let exported = AutomationFacts.chart(chart)
            try require(exported["knownPillarCount"]?.intValue == 3 && exported["pillars"]?["hour"] == .null, "未知时刻被补造为时柱。")
            return exported
        },
        proof("missing.boundary-time", "交节日缺时刻时保留多候选", .missingData, "立春日未知时刻保留前后年柱分支", tool: .chartContext) {
            let charts = try FourPillarsEngine().natalCharts(for: BirthProfile(birthYear: 2026, birthMonth: 2, birthDay: 4))
            try require(charts.count >= 2 && Set(charts.map(\.year.text)) == Set(["乙巳", "丙午"]) && charts.allSatisfy { $0.hour == nil }, "交节日缺少时刻时错误选择唯一命盘。")
            return .array(charts.map { .string($0.year.text) })
        },
        Check(id: "missing.unsourced-claim", title: "无来源事实不得通过复核", category: .missingData) {
            let claim = AgentClaim(text: "没有提供依据的事实", evidenceType: .deterministicFact)
            let runtime = AgentRuntime(driver: ClosureModelGateway { _ in AgentModelResponse(text: "合成答复", claims: [claim]) }, tools: TypedToolRegistry())
            let result = try await runtime.run(AgentRequest(requestID: "missing.unsourced-claim", text: "核对无来源事实", mode: .quick))
            try require(result.answer.degraded && result.answer.critic.unsupportedClaims.contains(claim.text) && result.quality?.citedFactCount == 0, "无来源事实被错误视为已核验。")
            return "真实运行时标记无来源断言并降级；引用 0/1。"
        },
        Check(id: "missing.tool-data", title: "资料读取失败后保留缺失提示", category: .missingData) {
            let source = "synthetic:missing-profile"
            let model = ClosureModelGateway { request in
                request.step == 1 ? AgentModelResponse(toolCalls: [AgentToolCall(name: .profileContext)], finished: false) :
                    AgentModelResponse(text: "资料缺失", claims: [AgentClaim(text: "档案事实", sourceRef: source, sourceRevision: "r1", evidenceType: .deterministicFact)])
            }
            let tools = TypedToolRegistry(handlers: [.profileContext: { _ in throw AgentToolError(name: .profileContext, message: "合成档案不存在") }])
            let runtime = AgentRuntime(driver: model, tools: tools)
            let result = try await runtime.run(AgentRequest(requestID: "missing.tool-data", text: "核对档案", mode: .quick))
            try require(result.answer.degraded && !result.answer.critic.missingEvidence.isEmpty && result.ledger.records.isEmpty, "读取失败后虚构了档案证据。")
            return "真实工具抛出缺资料错误后，运行时保留缺失依据且账本为空。"
        },
        Check(id: "missing.knowledge-hit", title: "空知识检索不能引用不存在的条目", category: .missingData) {
            let runtime = makeRuntime(tool: .knowledgeSearch, payload: .array([]), source: "synthetic:search",
                                      evidenceType: .knowledgeText,
                                      claim: AgentClaim(text: "不存在的知识正文", sourceRef: "synthetic:unread-entry", sourceRevision: "r1", evidenceType: .knowledgeText))
            let result = try await runtime.run(AgentRequest(requestID: "missing.knowledge-hit", text: "引用未检索到的知识", mode: .quick))
            try require(result.answer.degraded && !result.answer.critic.missingEvidence.isEmpty && result.quality?.citedFactCount == 0, "空检索被当成已经读取知识正文。")
            return "空检索实际经过运行时；未读知识条目的引用计为 0/1。"
        }
    ] }

    private static var conflictChecks: [Check] { [
        Check(id: "conflict.stale-revision", title: "旧版本引用不能绑定新事实", category: .conflicts) {
            let runtime = makeRuntime(tool: .dayContext, payload: .string("新版日期事实"), revision: "r2",
                                      claim: AgentClaim(text: "旧版断言", sourceRef: "synthetic:source", sourceRevision: "r1", evidenceType: .deterministicFact))
            let result = try await runtime.run(AgentRequest(requestID: "conflict.stale-revision", text: "核对旧版引用", mode: .quick))
            try require(result.answer.degraded && result.answer.critic.staleSources.contains("synthetic:source") && result.quality?.citedFactCount == 0, "过期版本引用被错误接受。")
            return "真实运行时拒绝旧 revision；引用 0/1。"
        },
        Check(id: "conflict.two-revisions", title: "同一来源发生版本冲突", category: .conflicts) {
            let counter = Counter()
            let model = ClosureModelGateway { request in
                if request.step <= 2 { return AgentModelResponse(toolCalls: [AgentToolCall(name: .dayContext)], finished: false) }
                return AgentModelResponse(text: "版本冲突", claims: [AgentClaim(text: "冲突事实", sourceRef: "synthetic:changing", sourceRevision: "r2", evidenceType: .deterministicFact)])
            }
            let tools = TypedToolRegistry(handlers: [.dayContext: { call in
                let n = await counter.next()
                return AgentToolResult(callID: call.id, name: .dayContext, payload: .number(Double(n)), sourceRef: "synthetic:changing", sourceRevision: "r\(n)")
            }])
            let runtime = AgentRuntime(driver: model, tools: tools)
            let result = try await runtime.run(AgentRequest(requestID: "conflict.two-revisions", text: "复核变化的资料", mode: .deep))
            try require(result.answer.degraded && result.answer.critic.conflicts.contains("synthetic:changing") && result.ledger.records.contains { !$0.conflictSet.isEmpty } && result.quality?.citedFactCount == 0, "多版本冲突被静默消解。")
            return "两次真实工具读取产生不同版本，账本保留冲突，引用不计通过。"
        },
        Check(id: "conflict.request-content", title: "同一请求ID的不同内容被拒绝", category: .conflicts) {
            try isolated { root in
                var journal = try AutomationMutationJournal(fileURL: root.appendingPathComponent("receipts.json"))
                let original = try journal.prepare(plan("conflict.request-content"))
                let bytes = try Data(contentsOf: journal.fileURL)
                var changed = original; changed.fingerprint = "different-content"
                try expectJournalError(.requestIDConflict) { _ = try journal.prepare(changed) }
                try require(try Data(contentsOf: journal.fileURL) == bytes, "拒绝冲突时修改了凭据。")
                return "真实 Journal 拒绝 request ID 内容冲突，原凭据字节不变。临时目录已清理。"
            }
        },
        Check(id: "conflict.stale-writer", title: "陈旧写入器不能擦除其他凭据", category: .conflicts) {
            try isolated { root in
                let url = root.appendingPathComponent("receipts.json")
                var first = try AutomationMutationJournal(fileURL: url), stale = try AutomationMutationJournal(fileURL: url)
                let prepared = try first.prepare(plan("writer-first"))
                try expectJournalError(.concurrentModification) { _ = try stale.prepare(plan("writer-second")) }
                try require(try AutomationMutationJournal(fileURL: url).records == [prepared] && stale.records.isEmpty, "陈旧写入器覆盖了现有凭据。")
                return "真实 Journal 检测并发修改并保留先前记录。临时目录已清理。"
            }
        },
        Check(id: "conflict.tampered-plan", title: "写入目标快照与版本不符被拒绝", category: .conflicts) {
            try isolated { root in
                var journal = try AutomationMutationJournal(fileURL: root.appendingPathComponent("receipts.json"))
                var tampered = try plan("tampered-plan"); tampered.desiredRevision = "invalid-revision"
                try expectJournalError(.invalidPlan) { _ = try journal.prepare(tampered) }
                try require(journal.records.isEmpty && !FileManager.default.fileExists(atPath: journal.fileURL.path), "无效目标快照仍生成了凭据。")
                return "真实 Journal 校验目标快照摘要；不匹配时不创建凭据。临时目录已清理。"
            }
        }
    ] }

    private static var writeChecks: [Check] { [
        Check(id: "write.event", title: "日程写入后校验并完成凭据", category: .localWrites) {
            try isolated { root in
                let store = EventRepository(fileURL: root.appendingPathComponent("events.json"))
                var journal = try AutomationMutationJournal(fileURL: root.appendingPathComponent("receipts.json"))
                let event = CalendarEvent(title: "合成面试准备", start: try date("2026-09-28T09:00:00+08:00"))
                let desired = try value(event)
                let prepared = try journal.prepare(plan("write.event", entityID: event.id, desired: desired))
                try store.save([event])
                try verifyAndComplete(&journal, prepared, actual: value(store.load().first))
                return "真实 EventRepository 与 Journal 完成写入、回读版本校验和凭据重载。组件检查，临时目录已清理。"
            }
        },
        noteWrite("write.journal", title: "日笺写入后保留正文与版本", insight: false),
        noteWrite("write.insight", title: "分析写入保留档案版本与作者", insight: true),
        Check(id: "write.event-update", title: "更新日程保留前后版本", category: .localWrites) {
            try isolated { root in
                let store = EventRepository(fileURL: root.appendingPathComponent("events.json"))
                var journal = try AutomationMutationJournal(fileURL: root.appendingPathComponent("receipts.json"))
                let event = CalendarEvent(title: "合成旧安排", start: try date("2026-09-28T09:00:00+08:00"))
                try store.save([event])
                let oldRevision = try AutomationSnapshot.revision(value(store.load().first))
                var updated = event; updated.title = "合成新安排"
                var proposal = try plan("write.event-update", entityID: event.id, desired: value(updated))
                proposal.method = "events.update"; proposal.expectedRevision = oldRevision
                let prepared = try journal.prepare(proposal)
                try require(try AutomationSnapshot.revision(value(store.load().first)) == prepared.expectedRevision, "更新前版本检查失败。")
                try store.save([updated])
                try verifyAndComplete(&journal, prepared, actual: value(store.load().first))
                try require(prepared.desiredRevision != oldRevision, "更新后版本没有变化。")
                return "真实仓库更新前比较旧版本，更新后回读新版本并完成 Journal。组件检查，临时目录已清理。"
            }
        },
        Check(id: "write.undo-event", title: "撤销创建后回读为空并保留两份凭据", category: .localWrites) {
            try isolated { root in
                let store = EventRepository(fileURL: root.appendingPathComponent("events.json"))
                var journal = try AutomationMutationJournal(fileURL: root.appendingPathComponent("receipts.json"))
                let event = CalendarEvent(title: "合成待撤销安排", start: try date("2026-09-28T09:00:00+08:00"))
                let created = try journal.prepare(plan("write.undo-event.create", entityID: event.id, desired: value(event)))
                try store.save([event]); try verifyAndComplete(&journal, created, actual: value(store.load().first))
                let undo = AutomationMutationPlan(requestID: "write.undo-event.delete", fingerprint: "undo", method: "events.delete", entity: "events", entityID: event.id, expectedRevision: created.desiredRevision)
                let prepared = try journal.prepare(undo)
                try require(try AutomationSnapshot.revision(value(store.load().first)) == prepared.expectedRevision, "撤销时目标版本不匹配。")
                try store.save([])
                try require(try store.load().isEmpty, "撤销后仍可读到被创建的日程。")
                _ = try journal.complete(requestID: prepared.requestID, fingerprint: prepared.fingerprint, result: .object(["deleted": .bool(true)]))
                try require(try AutomationMutationJournal(fileURL: journal.fileURL).records.filter { $0.state == .completed }.count == 2, "创建与撤销凭据未完整保留。")
                return "真实仓库执行合成创建与撤销，回读为空，Journal 保留两份完成凭据。非 Router/UI 端到端。"
            }
        }
    ] }

    private static func noteWrite(_ id: String, title: String, insight: Bool) -> Check {
        Check(id: id, title: title, category: .localWrites) {
            try isolated { root in
                let store = DayNoteRepository(fileURL: root.appendingPathComponent("notes.json"))
                var journal = try AutomationMutationJournal(fileURL: root.appendingPathComponent("receipts.json"))
                let note = DayNote(kind: insight ? .insight : .journal, date: "2026-09-28",
                                   profileID: insight ? UUID() : nil, title: title, body: "仅用于固定评测的合成正文。",
                                   source: .agent, author: "合成评测", createdAt: try date("2026-09-28T04:00:00Z"),
                                   profileRevision: insight ? "synthetic-profile-r1" : nil,
                                   strengthAssessment: insight ? .strong : nil)
                var proposal = try plan(id, entityID: note.id, desired: value(note))
                proposal.entity = "notes"; proposal.method = insight ? "insights.create" : "journal.create"
                let prepared = try journal.prepare(proposal)
                try store.save([note])
                let loaded = try store.load()
                try require(loaded == [note], "日笺字段在保存后发生变化。")
                try verifyAndComplete(&journal, prepared, actual: value(loaded.first))
                return "真实 DayNoteRepository 回读完整合成记录，Journal 校验版本并完成。组件检查，临时目录已清理。"
            }
        }
    }

    private static var replayChecks: [Check] { [
        Check(id: "repeat.prepared-restart", title: "重启后重复准备复用原实体", category: .repeatedRequests) {
            try isolated { root in
                let url = root.appendingPathComponent("receipts.json")
                var journal = try AutomationMutationJournal(fileURL: url)
                let prepared = try journal.prepare(plan("repeat.prepared-restart"))
                var restarted = try AutomationMutationJournal(fileURL: url)
                let replacement = try plan("repeat.prepared-restart")
                try require(replacement.entityID != prepared.entityID, "合成重试未生成不同候选实体。")
                let replay = try restarted.prepare(replacement)
                try require(replay == prepared && restarted.records.count == 1, "准备态重试改变了实体或新增了凭据。")
                return "真实 Journal 重载后复用原 UUID、目标和准备时间。临时目录已清理。"
            }
        },
        Check(id: "repeat.completed-replay", title: "完成请求重放返回原回执", category: .repeatedRequests) {
            try isolated { root in
                let url = root.appendingPathComponent("receipts.json")
                var journal = try AutomationMutationJournal(fileURL: url)
                let prepared = try journal.prepare(plan("repeat.completed-replay"))
                let completed = try journal.complete(requestID: prepared.requestID, fingerprint: prepared.fingerprint, result: .string("original-receipt"))
                var restarted = try AutomationMutationJournal(fileURL: url)
                let replay = try restarted.complete(requestID: prepared.requestID, fingerprint: prepared.fingerprint, result: .string("different-receipt"))
                try require(replay == completed && restarted.records.count == 1, "重放覆盖了原完成回执。")
                return "真实 Journal 对重复完成返回原结果，不覆盖回执或新增记录。临时目录已清理。"
            }
        },
        Check(id: "repeat.canonical-fingerprint", title: "对象键顺序不改变幂等指纹", category: .repeatedRequests) {
            try isolated { root in
                var journal = try AutomationMutationJournal(fileURL: root.appendingPathComponent("receipts.json"))
                let a = JSONValue.object(["title": .string("合成事项"), "day": .number(28)])
                let b = JSONValue.object(["day": .number(28), "title": .string("合成事项")])
                var first = try plan("repeat.canonical-fingerprint", desired: a)
                first.fingerprint = try AutomationSnapshot.revision(a)
                let saved = try journal.prepare(first)
                var reordered = first; reordered.desired = b; reordered.fingerprint = try AutomationSnapshot.revision(b)
                try require(try journal.prepare(reordered) == saved && journal.records.count == 1, "同义对象键顺序生成了不同幂等请求。")
                return "真实规范化摘要和 Journal 复用同义请求；仅保留一条记录。临时目录已清理。"
            }
        }
    ] }

    private actor Counter {
        private var count = 0
        func next() -> Int { count += 1; return count }
        func value() -> Int { count }
    }

    private static var interruptionChecks: [Check] { [
        Check(id: "interrupt.before-start", title: "运行前取消不调用模型", category: .cancellationTimeout) {
            let calls = Counter()
            let runtime = AgentRuntime(driver: ClosureModelGateway { _ in
                _ = await calls.next(); return AgentModelResponse(text: "不应调用")
            }, tools: TypedToolRegistry())
            await runtime.cancel(requestID: "interrupt.before-start")
            do {
                _ = try await runtime.run(AgentRequest(requestID: "interrupt.before-start", text: "合成取消"))
                throw Failure(detail: "取消后的任务仍成功执行。")
            } catch AgentRuntimeError.cancelled { }
            try require(await calls.value() == 0, "预先取消仍调用了模型。")
            return "真实运行时在模型调用前响应取消，调用数为零。"
        },
        Check(id: "interrupt.in-flight", title: "模型运行中取消阻止下一轮", category: .cancellationTimeout) {
            let calls = Counter()
            let runtime = AgentRuntime(driver: ClosureModelGateway { _ in
                _ = await calls.next()
                try await Task.sleep(nanoseconds: 100_000_000)
                return AgentModelResponse(toolCalls: [AgentToolCall(name: .dayContext)], finished: false)
            }, tools: TypedToolRegistry())
            let task = Task { try await runtime.run(AgentRequest(requestID: "interrupt.in-flight", text: "合成运行中取消", mode: .deep)) }
            return try await withTaskCancellationHandler {
                while await calls.value() == 0 {
                    try Task.checkCancellation()
                    await Task.yield()
                }
                await runtime.cancel(requestID: "interrupt.in-flight")
                do { _ = try await task.value; throw Failure(detail: "运行中取消后任务仍成功结束。") }
                catch AgentRuntimeError.cancelled { }
                try require(await calls.value() == 1, "取消后仍发起下一轮模型调用。")
                return "真实运行时在首轮模型返回后停止，没有第二次调用。"
            } onCancel: { task.cancel() }
        },
        Check(id: "interrupt.model-timeout", title: "真实超时终止有限循环", category: .cancellationTimeout) {
            let calls = Counter()
            let runtime = AgentRuntime(driver: ClosureModelGateway { _ in
                _ = await calls.next()
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return AgentModelResponse(text: "过迟的答复")
            }, tools: TypedToolRegistry(), budget: AgentBudget(maxModelCalls: 2, timeoutSeconds: 0.1))
            let result = try await runtime.run(AgentRequest(requestID: "interrupt.model-timeout", text: "合成超时", mode: .quick))
            let trace = await runtime.trace(result.traceID)
            try require(result.answer.degraded && trace?.modelCalls == 1 && trace?.events.contains { $0.phase == .failed } == true, "超时后未降级或仍继续模型循环。")
            try require(await calls.value() == 1, "超时后仍重试模型。")
            return "协作式延迟模型触发真实 0.1 秒超时；运行时降级且不重试。"
        }
    ] }

    private static func isolated<T>(_ body: (URL) throws -> T) throws -> T {
        try Task.checkCancellation()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lingxi-evaluation-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try body(root)
        try FileManager.default.removeItem(at: root)
        return result
    }

    private static func plan(_ id: String, entityID: UUID = UUID(), desired: JSONValue = .string("synthetic-target")) throws -> AutomationMutationPlan {
        AutomationMutationPlan(requestID: id, fingerprint: "synthetic-fingerprint", method: "events.create",
                               entity: "events", entityID: entityID, desired: desired,
                               desiredRevision: try AutomationSnapshot.revision(desired),
                               preparedAt: try date("2026-09-28T04:00:00Z"))
    }

    private static func verifyAndComplete(_ journal: inout AutomationMutationJournal, _ prepared: AutomationMutationPlan, actual: JSONValue) throws {
        try require(try AutomationSnapshot.revision(actual) == prepared.desiredRevision, "真实仓库回读版本与提议不一致。")
        let receipt = JSONValue.object(["revision": .string(prepared.desiredRevision ?? ""), "saved": .bool(true)])
        _ = try journal.complete(requestID: prepared.requestID, fingerprint: prepared.fingerprint, result: receipt)
        let reloaded = try AutomationMutationJournal(fileURL: journal.fileURL)
        try require(reloaded.records.contains { $0.requestID == prepared.requestID && $0.state == .completed && $0.result == receipt }, "已完成凭据未能从磁盘重载。")
    }

    private static func expectJournalError(_ expected: AutomationMutationJournalError, _ body: () throws -> Void) throws {
        do { try body(); throw Failure(detail: "Journal 接受了本应拒绝的合成请求。") }
        catch let error as AutomationMutationJournalError {
            try require(error == expected, "Journal 返回的错误类别与固定预期不符。")
        }
    }
}
