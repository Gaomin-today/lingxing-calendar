import SwiftUI
import LingxiAgent

/// An in-memory inspection workspace. Closing it does not alter records or stop evaluations.
struct AgentQualityView: View {
    @ObservedObject var store: AgentQualityStore
    var initialRunID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PanelTab = .evidence
    @State private var selectedRunID: String?
    @State private var selectedCategory = "全部"
    @State private var confirmClear = false

    private enum PanelTab: String, CaseIterable {
        case evidence = "回答依据"
        case evaluation = "固定评测"
    }

    private struct SourceKey: Hashable {
        let sourceRef: String
        let revision: String?
        let retrievedAt: Date
        let type: EvidenceType
    }

    private var selectedRecord: AgentRunInspection? {
        store.records.first { $0.id == selectedRunID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack {
                Picker("面板", selection: $selectedTab) {
                    ForEach(PanelTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
                Spacer()
                if selectedTab == .evidence {
                    Text("仅保留本次运行的最近 30 条任务")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                } else {
                    Pill(text: "\(AgentEvaluationSuite.caseCount) 个固定用例")
                }
            }
            if selectedTab == .evidence { evidencePanel }
            else { evaluationPanel }
            HStack {
                Image(systemName: "internaldrive").foregroundStyle(Theme.secondary)
                Text(selectedTab == .evidence
                     ? "依据记录仅存于内存；移除或清空会保留聊天正文，关闭面板会保留记录。"
                     : "关闭面板不会停止评测；评测结果仅保留在本次运行中。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(QuietButton())
            }
        }
        .padding(24).frame(width: 950, height: 720)
        .background(Theme.paper).foregroundStyle(Theme.ink).preferredColorScheme(.light)
        .onAppear { selectedRunID = initialRunID ?? store.records.first?.id }
        .onChange(of: store.records.map(\.id)) { _, ids in
            if selectedRunID == nil && initialRunID == nil {
                selectedRunID = ids.first
            }
        }
        .onChange(of: store.isEvaluating) { _, running in
            if running { selectedCategory = "全部" }
        }
        .alert("清空本次运行的任务记录？", isPresented: $confirmClear) {
            Button("清空记录", role: .destructive) { store.clearRecords() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将移除此面板中的所有任务依据与执行摘要，不会修改日程、聊天或配置。")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("依据与质量").font(.system(size: 24, weight: .medium, design: .serif))
                Text("查看回答使用了什么依据，以及固定用例的运行结果。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").padding(6) }
                .buttonStyle(.plain).accessibilityLabel("关闭依据与质量面板")
        }
    }

    private var evidencePanel: some View {
        HStack(alignment: .top, spacing: 18) {
            recentRecords.frame(width: 222)
            Rectangle().fill(Theme.line).frame(width: 1)
            if let record = selectedRecord {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        recordOverview(record)
                        if let quality = record.result?.quality { claimAssessments(quality) }
                        if let result = record.result { sourceRecords(result.ledger.records) }
                        if let critic = record.result?.answer.critic ?? record.trace?.critic {
                            criticDetails(critic, quality: record.result?.quality)
                        }
                        if let trace = record.trace { traceDetails(trace) }
                        else {
                            Card { emptyNote("没有执行摘要", detail: "此任务没有可展示的阶段记录。", symbol: "list.bullet.rectangle") }
                        }
                    }.padding(.trailing, 3)
                }
            } else {
                emptyNote(selectedRunID == nil ? "还没有任务记录" : "所选任务记录已不可用",
                          detail: selectedRunID == nil
                            ? "完成一次 Agent 回答后，可在这里查看其来源、版本绑定与执行摘要。"
                            : "该记录已清除或超出最近 30 条范围，聊天正文不受影响。可从左侧选择其他任务。",
                          symbol: "text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(maxHeight: .infinity)
    }

    private var recentRecords: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近任务").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(store.records.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.records) { record in
                        Button { selectedRunID = record.id } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(record.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11, weight: .medium))
                                    Spacer(minLength: 0)
                                    if selectedRunID == record.id { Image(systemName: "checkmark").font(.system(size: 10)) }
                                }
                                HStack(spacing: 6) {
                                    Text(modeLabel(record)).font(.system(size: 10))
                                    Text("·").foregroundStyle(Theme.secondary)
                                    Text(recordStatus(record)).font(.system(size: 10)).foregroundStyle(recordColor(record))
                                }
                                Text(record.model.isEmpty ? "模型未记录" : record.model)
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
                                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedRunID == record.id ? Theme.softJade : Theme.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedRunID == record.id ? Theme.jade.opacity(0.35) : Theme.line))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(record.finishedAt.formatted(date: .abbreviated, time: .shortened))，\(modeLabel(record))，\(recordStatus(record))，模型 \(record.model)")
                    }
                }
            }
            Button("清空任务记录") { confirmClear = true }
                .buttonStyle(QuietButton()).font(.system(size: 11)).disabled(store.records.isEmpty)
        }
    }

    private func recordOverview(_ record: AgentRunInspection) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("任务概览").font(.system(size: 15, weight: .semibold))
                        Text(record.finishedAt.formatted(date: .complete, time: .standard))
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Pill(text: recordStatus(record), color: recordColor(record))
                    Button("移除此条") { store.removeRecord(id: record.id) }
                        .buttonStyle(QuietButton()).font(.system(size: 10))
                        .accessibilityLabel("移除当前任务的依据和执行摘要")
                }
                HStack(alignment: .top, spacing: 12) {
                    metric("引用覆盖率", value: coverageLabel(record.result?.quality),
                           note: coverageNote(record.result?.quality))
                    metric("来源", value: record.result.map { String($0.ledger.sourceCount) } ?? "—", note: "不同来源引用")
                    metric("耗时", value: record.trace?.duration.map(durationLabel) ?? "未记录", note: "任务运行时间")
                }
                Text("只统计结构化事实声明的来源与版本绑定，不代表模型结论正确；普通文本未评估。推断和用户输入不计入分母。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(Theme.line)
                metadata("模式", modeLabel(record))
                metadata("模型", record.model.isEmpty ? "未记录" : record.model)
                metadata("任务 ID", record.id, monospaced: true)
                if let failure = record.failure ?? record.trace?.failure {
                    issueText("未完成原因", failure)
                }
                if record.result == nil {
                    Text("此任务没有完整回答结果，不能据此计算引用覆盖率。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func claimAssessments(_ quality: AgentQualityReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("结构化声明", count: quality.claims.count)
                if quality.claims.isEmpty {
                    Text("没有可评估的结构化声明，普通回答文本未纳入质量评估。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                } else {
                    ForEach(Array(quality.claims.enumerated()), id: \.offset) { index, assessment in
                        if index > 0 { Divider().overlay(Theme.line) }
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top) {
                                Text("\(index + 1)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.secondary)
                                Text(assessment.claim.text).font(.system(size: 11)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            HStack(spacing: 6) {
                                Pill(text: evidenceLabel(assessment.claim.evidenceType))
                                Pill(text: assessment.status.rawValue,
                                     color: assessmentColor(assessment))
                            }
                            if let source = assessment.claim.sourceRef { metadata("sourceRef", source, monospaced: true) }
                            if let revision = assessment.claim.sourceRevision { metadata("revision", revision, monospaced: true) }
                        }
                    }
                }
            }
        }
    }

    private func sourceRecords(_ records: [EvidenceRecord]) -> some View {
        var seen = Set<SourceKey>()
        let sources = records.filter {
            seen.insert(SourceKey(sourceRef: $0.sourceRef, revision: $0.sourceRevision,
                                  retrievedAt: $0.retrievedAt, type: $0.evidenceType)).inserted
        }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("读取的来源", count: sources.count)
                Text("这里列出读取时的依据记录，不表示每一条都已被回答引用。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                if sources.isEmpty {
                    Text("此任务没有来源记录。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                } else {
                    ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                        if index > 0 { Divider().overlay(Theme.line) }
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("来源 \(index + 1)").font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Pill(text: evidenceLabel(source.evidenceType))
                            }
                            Text(source.claim).font(.system(size: 11)).textSelection(.enabled)
                            metadata("sourceRef", source.sourceRef, monospaced: true)
                            metadata("revision", source.sourceRevision ?? "未提供", monospaced: true)
                            metadata("retrievedAt", source.retrievedAt.formatted(date: .numeric, time: .complete))
                            metadata("type", source.evidenceType.rawValue, monospaced: true)
                            if !source.conflictSet.isEmpty {
                                issueText("冲突记录", source.conflictSet.joined(separator: "\n"))
                            }
                        }
                    }
                }
            }
        }
    }

    private func criticDetails(_ critic: AgentCriticReport, quality: AgentQualityReport?) -> some View {
        let hasFactClaims = (quality?.factClaimCount ?? 0) > 0
        return Card {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("校验缺项与冲突").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Pill(text: hasFactClaims ? (critic.passed ? "结构化校验通过" : "待核对") : "未评估结构化事实",
                         color: hasFactClaims ? (critic.passed ? Theme.jade : Theme.vermilion) : Theme.secondary)
                }
                if critic.missingEvidence.isEmpty && critic.conflicts.isEmpty && critic.staleSources.isEmpty && critic.unsupportedClaims.isEmpty {
                    Text(!hasFactClaims ? "没有可评估的结构化事实，普通文本未评估。" : (critic.passed ? "没有报告结构化缺项或冲突。普通文本仍未评估。" : "校验未通过，暂无具体问题条目。"))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                issueList("缺少依据", critic.missingEvidence)
                issueList("存在冲突", critic.conflicts)
                issueList("来源已过期", critic.staleSources)
                issueList("声明缺乏支持", critic.unsupportedClaims)
                if critic.needsSupplementalRead {
                    Text("校验建议补充读取资料。").font(.system(size: 10)).foregroundStyle(Theme.vermilion)
                }
            }
        }
    }

    private func traceDetails(_ trace: AgentTrace) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("执行摘要").font(.system(size: 13, weight: .semibold))
                HStack(alignment: .top, spacing: 12) {
                    metric("网关步骤", value: String(trace.modelCalls), note: "含种子读取")
                    metric("工具调用", value: String(trace.toolCalls), note: "执行次数")
                    metric("读取轮次", value: String(trace.loopRounds), note: trace.degraded ? "已降级返回" : "未降级")
                }
                Text("网关步骤包含种子读取步骤，不等于实际 HTTP 请求数。以下仅展示阶段摘要。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                if trace.events.isEmpty {
                    Text("没有记录执行阶段。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                } else {
                    ForEach(Array(trace.events.enumerated()), id: \.offset) { index, event in
                        if index > 0 { Divider().overlay(Theme.line) }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: event.success ? "checkmark.circle" : "exclamationmark.circle")
                                .foregroundStyle(event.success ? Theme.jade : Theme.vermilion)
                                .accessibilityLabel(event.success ? "阶段完成" : "阶段未成功")
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(phaseLabel(event.phase)).font(.system(size: 11, weight: .semibold))
                                    Spacer()
                                    Text(event.at.formatted(date: .omitted, time: .standard))
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary)
                                }
                                Text(event.summary).font(.system(size: 11)).textSelection(.enabled)
                                if let tool = event.toolName { metadata("工具", tool.rawValue, monospaced: true) }
                                if !event.sourceRefs.isEmpty { metadata("来源", event.sourceRefs.joined(separator: "\n"), monospaced: true) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var evaluationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("固定评测").font(.system(size: 15, weight: .semibold))
                            Text("本机合成用例，不联网，也不读取个人数据。")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        if store.isEvaluating {
                            ProgressView().controlSize(.small).accessibilityLabel("评测正在运行")
                            Button("停止评测") { store.cancelEvaluations() }.buttonStyle(QuietButton())
                        } else {
                            Button(store.evaluation == nil ? "运行固定评测" : "重新运行") { store.runEvaluations() }.buttonStyle(JadeButton())
                        }
                    }
                    Text("写入用例只检查临时数据与写入回执，不会改动实际日程，也不代表完整业务操作已通过。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let report = store.evaluation {
                        HStack(alignment: .top, spacing: 18) {
                            metric("已完成", value: "\(report.totalCount) / \(AgentEvaluationSuite.caseCount)", note: evaluationState(cancelled: report.cancelled, completed: report.totalCount))
                            metric("通过", value: String(report.passedCount), note: "已完成用例", color: Theme.jade)
                            metric("失败", value: String(report.failedCount), note: "需检查详情", color: report.failedCount > 0 ? Theme.vermilion : Theme.secondary)
                        }
                        metadata("开始", report.startedAt.formatted(date: .abbreviated, time: .standard))
                        metadata("结束", report.endedAt.formatted(date: .abbreviated, time: .standard))
                        if report.cancelled {
                            Text("评测已取消；以下保留已完成项，未执行用例没有判定结果。")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.vermilion)
                        } else if !store.isEvaluating && report.totalCount < AgentEvaluationSuite.caseCount {
                            Text("评测尚未完整执行，不能视为全部通过。")
                                .font(.system(size: 11)).foregroundStyle(Theme.vermilion)
                        }
                    }
                }
            }
            if let report = store.evaluation, !report.results.isEmpty {
                let categories = Array(Set(report.results.map { $0.category.rawValue })).sorted()
                HStack {
                    Text("用例结果").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Picker("筛选分类", selection: $selectedCategory) {
                        Text("全部分类").tag("全部")
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }.frame(width: 230)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(report.results.filter { selectedCategory == "全部" || $0.category.rawValue == selectedCategory }, id: \.id) { result in
                            evaluationRow(title: result.title, category: result.category.rawValue, passed: result.passed,
                                          detail: result.detail, duration: result.duration)
                        }
                    }.padding(.trailing, 3)
                }
            } else {
                emptyNote(store.isEvaluating ? "正在运行合成用例" : "尚无评测结果",
                          detail: store.isEvaluating ? "结束或停止后会显示已完成的用例，可随时停止。" : "点击运行后查看各项检查结果；尚未运行的用例不计为通过或失败。",
                          symbol: store.isEvaluating ? "hourglass" : "checklist")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(maxHeight: .infinity)
    }

    private func evaluationRow(title: String, category: String, passed: Bool, detail: String, duration: TimeInterval) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 17)).foregroundStyle(passed ? Theme.jade : Theme.vermilion)
                    .accessibilityLabel(passed ? "通过" : "失败")
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(title).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Pill(text: passed ? "通过" : "失败", color: passed ? Theme.jade : Theme.vermilion)
                    }
                    Text(detail).font(.system(size: 11)).foregroundStyle(passed ? Theme.secondary : Theme.vermilion)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    HStack {
                        Text(category)
                        Spacer()
                        Text(durationLabel(duration)).monospacedDigit()
                    }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func metric(_ title: String, value: String, note: String, color: Color = Theme.ink) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.65)
            Text(note).font(.system(size: 9)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)：\(value)，\(note)")
    }

    private func metadata(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondary).frame(width: 72, alignment: .leading)
            Text(value).font(.system(size: 10, design: monospaced ? .monospaced : .default))
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.accessibilityElement(children: .combine)
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(count) 项").font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }
    }

    private func emptyNote(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Theme.jade)
            Text(title).font(.system(size: 14, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 370)
        }.padding(20).frame(maxWidth: .infinity)
    }

    private func issueText(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold))
            Text(content).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.foregroundStyle(Theme.vermilion)
    }

    @ViewBuilder private func issueList(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty { issueText(title, items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")) }
    }

    private func modeLabel(_ record: AgentRunInspection) -> String {
        guard let mode = record.result?.answer.mode ?? record.trace?.mode else { return "模式未记录" }
        return mode == .deep ? "深度解读" : "快速回答"
    }

    private func recordStatus(_ record: AgentRunInspection) -> String {
        if record.failure != nil || record.trace?.failure != nil { return "未完成" }
        if record.result?.answer.degraded == true || record.trace?.degraded == true { return "降级返回" }
        return record.result == nil ? "无完整结果" : "已完成"
    }

    private func recordColor(_ record: AgentRunInspection) -> Color {
        recordStatus(record) == "已完成" ? Theme.jade : Theme.vermilion
    }

    private func assessmentColor(_ assessment: AgentClaimAssessment) -> Color {
        if assessment.claim.evidenceType == .modelInference || assessment.claim.evidenceType == .userInput { return Theme.secondary }
        return assessment.isCited ? Theme.jade : Theme.vermilion
    }

    private func coverageLabel(_ quality: AgentQualityReport?) -> String {
        guard let quality, let coverage = quality.citationCoverage, coverage.isFinite else { return "未评估" }
        return String(format: "%.0f%%", coverage * 100)
    }

    private func coverageNote(_ quality: AgentQualityReport?) -> String {
        guard let quality, quality.factClaimCount > 0 else { return "无可计分的事实声明" }
        return "\(quality.citedFactCount) / \(quality.factClaimCount) 条事实已绑定"
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        duration < 1 ? String(format: "%.0f ms", duration * 1_000) : String(format: "%.1f s", duration)
    }

    private func evaluationState(cancelled: Bool, completed: Int) -> String {
        if store.isEvaluating { return "正在运行" }
        if cancelled { return "已取消，保留完成项" }
        return completed == AgentEvaluationSuite.caseCount ? "全部用例已执行" : "尚未完整执行"
    }

    private func evidenceLabel(_ type: EvidenceType) -> String {
        switch type {
        case .deterministicFact: return "确定性事实"
        case .knowledgeText: return "资料文本"
        case .userInput: return "用户输入 · 不计分"
        case .modelInference: return "模型推断 · 不计分"
        }
    }

    private func phaseLabel(_ phase: AgentPhase) -> String {
        switch phase {
        case .classify: return "分类"
        case .loadSkill: return "读取 Skill"
        case .planEvidence: return "规划依据"
        case .retrieve: return "读取资料"
        case .draft: return "整理初稿"
        case .deterministicCheck: return "校验依据"
        case .critic: return "复核"
        case .repair: return "补读"
        case .final: return "完成"
        case .failed: return "未完成"
        case .cancelled: return "已停止"
        }
    }
}
