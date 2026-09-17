import SwiftUI
import AppKit
import LingxiCore

struct AgentTaskRequest: Identifiable {
    let id = UUID()
    let kind: AgentCalendarTaskKind
    let date: Date
    let referenceTime: String
    let profileID: UUID?
    let eventID: UUID?
}

struct AgentHandoffView: View {
    @ObservedObject var store: AppStore
    let request: AgentTaskRequest
    @Environment(\.dismiss) private var dismiss
    @State private var saveInsight = true
    @State private var additionalRequest = ""
    @State private var copied = false
    private var person: BirthProfile? { store.birthProfiles.profiles.first { $0.id == request.profileID } }
    private var taskText: String {
        AgentTaskComposer.compose(kind: request.kind,
            cliPath: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/lingxi").path,
            skillPath: Bundle.main.resourceURL?.appendingPathComponent("AgentSkill/SKILL.md").path ?? "AgentSkill/SKILL.md",
            preview: store.isPreviewMode, date: DateText.format(request.date, "yyyy-MM-dd"),
            referenceTime: request.referenceTime,
            profileID: person?.id, eventID: request.eventID, saveInsight: saveInsight, additionalRequest: additionalRequest)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("交给我的 Agent").font(.system(size: 25, weight: .medium, design: .serif))
                    Text(request.kind.title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer(); Button("关闭") { dismiss() }.buttonStyle(QuietButton())
            }
            HStack {
                Pill(text: DateText.format(request.date, "yyyy年M月d日"))
                Pill(text: person?.name ?? "未关联个人档案", color: Theme.accent)
                Spacer()
                if store.isPreviewMode { Pill(text: "隔离预览") }
            }
            Text("解读参考时刻：\(request.referenceTime) 北京时间（Asia/Shanghai）").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Text("复制下面的任务，发送给你使用的 Agent。它会通过本机 CLI 读取资料；回写的分析会出现在日笺中。复制后尚未开始执行。")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
            if !store.automationEnabled {
                Label("本机 CLI 访问已关闭，请先在“连接自己的 Agent”中开启。", systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(Theme.vermilion)
            }
            Toggle("将完成的分析保存到日笺", isOn: $saveInsight).toggleStyle(.checkbox).font(.system(size: 12))
            TextField("补充要求，例如：重点帮我准备明天的面试", text: $additionalRequest, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...3)
            ScrollView {
                Text(taskText).font(.system(size: 11, design: .monospaced)).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }.background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            HStack {
                Text(copied ? "已复制；发送给自己的 Agent 后即可继续。" : "支持能在本机执行命令的 Agent。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
                Button(copied ? "再次复制任务" : "复制完整任务") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(taskText, forType: .string); copied = true
                }.buttonStyle(JadeButton()).disabled(!store.automationEnabled)
            }
        }.padding(26).frame(width: 720, height: 740).background(Theme.paper)
    }
}
