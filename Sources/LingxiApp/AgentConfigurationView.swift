import SwiftUI
import AppKit
import LingxiAgent

/// Drafts stay local to this workspace until the user explicitly saves a file.
struct AgentConfigurationView: View {
    @ObservedObject var store: AgentConfigurationStore
    @ObservedObject var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDocument: AgentConfigDocument = .soul
    @State private var drafts: [AgentConfigDocument: String] = [:]
    @State private var selectedHistory: AgentConfigHistory?
    @State private var feedback: String?
    @State private var detailTab: DetailTab = .preview
    @State private var previewMode: PreviewMode = .saved
    @State private var pendingAction: PendingAction?

    private enum DetailTab: String, CaseIterable {
        case preview = "生效预览"
        case history = "版本历史"
    }

    private enum PreviewMode: String, CaseIterable {
        case saved = "已保存"
        case draft = "草稿（仅当前文件）"
    }

    private enum PendingAction: Identifiable {
        case close
        case discard(AgentConfigDocument)
        case reload(AgentConfigDocument)
        case replace(AgentConfigDocument, content: String, source: String)

        var id: String {
            switch self {
            case .close: return "close"
            case .discard(let document): return "discard-\(document.id)"
            case .reload(let document): return "reload-\(document.id)"
            case .replace(let document, _, _): return "replace-\(document.id)"
            }
        }

        var title: String {
            switch self {
            case .close: return "放弃未保存的草稿并关闭？"
            case .discard: return "丢弃当前文件的草稿？"
            case .reload: return "重新读取并覆盖当前草稿？"
            case .replace: return "用所选内容替换当前草稿？"
            }
        }

        var message: String {
            switch self {
            case .close: return "所有文档中尚未保存的修改都会丢失，已保存的配置不受影响。"
            case .discard(let document): return "\(document.rawValue) 将回到当前已保存的内容。"
            case .reload(let document): return "将从磁盘重新读取 \(document.rawValue)。读取成功后，当前草稿会被替换；读取失败时保留草稿。"
            case .replace(let document, _, let source): return "\(document.rawValue) 的现有草稿将被\(source)替换。载入后仍需点击保存才会生效。"
            }
        }

        var buttonTitle: String {
            switch self {
            case .close: return "放弃并关闭"
            case .discard: return "丢弃草稿"
            case .reload: return "重新读取"
            case .replace: return "替换草稿"
            }
        }
    }

    private var selectedContent: String { drafts[selectedDocument] ?? store.value(for: selectedDocument) }
    private var hasDraft: Bool { drafts[selectedDocument] != nil }
    private var hasAnyDraft: Bool { !drafts.isEmpty }
    private var selectedHistoryItems: [AgentConfigHistory] { store.history(for: selectedDocument) }

    private var validationError: String? {
        do {
            try AgentConfigurationRepository.validate(selectedDocument, content: selectedContent)
            return nil
        } catch {
            if selectedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedDocument != .user {
                return "\(selectedDocument.rawValue) 正文不能为空。"
            }
            return error.localizedDescription
        }
    }

    private var promptPreview: String {
        var values = store.values
        if previewMode == .draft { values[selectedDocument] = selectedContent }
        let snapshot = AgentConfigurationSnapshot(values: values)
        return AgentSystemPrompt.render(context: snapshot.promptContext(
            includeSystemData: appStore.cloudIncludeSystemData, snapshotID: "preview"
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            documentTabs
            HStack(alignment: .top, spacing: 18) {
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Theme.line).frame(width: 1)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(maxHeight: .infinity)
            footer
        }
        .padding(24)
        .frame(width: 900, height: 680)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(hasAnyDraft)
        .onExitCommand { requestClose() }
        .onChange(of: selectedDocument) { _, _ in
            selectedHistory = nil
            feedback = nil
        }
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text(action.title), message: Text(action.message),
                primaryButton: .destructive(Text(action.buttonTitle)) { perform(action) },
                secondaryButton: .cancel(Text("保留草稿"))
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("阿灵配置").font(.system(size: 23, weight: .medium, design: .serif))
                Text("保存后用于后续远程 AI 请求；进行中的回答继续使用开始时的配置。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if hasAnyDraft { Pill(text: "\(drafts.count) 份未保存草稿", color: Theme.vermilion) }
            Button { requestClose() } label: { Image(systemName: "xmark").padding(6) }
                .buttonStyle(.plain).accessibilityLabel("关闭阿灵配置")
        }
    }

    private var documentTabs: some View {
        HStack(spacing: 8) {
            ForEach(AgentConfigDocument.allCases) { document in
                Button { selectedDocument = document } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            Text(document.rawValue).font(.system(size: 12, weight: .semibold, design: .monospaced))
                            if drafts[document] != nil {
                                Circle().fill(Theme.vermilion).frame(width: 5, height: 5)
                                    .accessibilityLabel("未保存")
                            }
                        }
                        Text(document.title).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(selectedDocument == document ? Theme.softJade : Theme.card, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedDocument == document ? Theme.jade.opacity(0.35) : Theme.line))
                }.buttonStyle(.plain).foregroundStyle(selectedDocument == document ? Theme.jade : Theme.ink)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedDocument.title).font(.system(size: 14, weight: .semibold))
                Spacer()
                if hasDraft { Pill(text: "未保存", color: Theme.vermilion) }
                else if store.snapshots[selectedDocument]?.isDefault == true { Pill(text: "默认") }
                else { Pill(text: "已自定义") }
            }
            Text(selectedDocument.help).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: Binding(get: { selectedContent }, set: { updateDraft($0, for: selectedDocument) }))
                .id(selectedDocument)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8).frame(minHeight: store.loadErrors[selectedDocument] == nil ? 150 : 90, maxHeight: .infinity)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(validationError == nil ? Theme.line : Theme.vermilion))
                .accessibilityLabel("\(selectedDocument.rawValue) 正文")
            HStack {
                Text("\(selectedContent.count) / \(AgentConfigurationRepository.maximumCharacters) 字符")
                    .foregroundStyle(validationError == nil ? Theme.secondary : Theme.vermilion)
                Spacer()
                if selectedDocument == .user { Text("可留空").foregroundStyle(Theme.secondary) }
            }.font(.system(size: 10))
            if let validationError { errorText(validationError) }
            if let loadError = store.loadErrors[selectedDocument] {
                VStack(alignment: .leading, spacing: 6) {
                    errorText(loadError)
                    Text("请先在配置目录中修复或移走 \(selectedDocument.rawValue)，再点击“重新读取”。原文件会保留，载入默认草稿不会修复此错误。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开配置文件夹") { NSWorkspace.shared.open(store.directoryURL) }
                        .buttonStyle(QuietButton()).font(.system(size: 10))
                }
            }
            HStack(spacing: 7) {
                Button("载入默认") {
                    requestReplacement(selectedDocument.defaultContent, for: selectedDocument, source: "默认内容")
                }.buttonStyle(QuietButton())
                Button("重新读取") {
                    if hasDraft { pendingAction = .reload(selectedDocument) }
                    else { reload(selectedDocument) }
                }.buttonStyle(QuietButton()).help("从磁盘重新读取当前文件和版本，可解决其他程序修改造成的版本冲突。")
                Spacer(minLength: 0)
                Button("丢弃草稿") { pendingAction = .discard(selectedDocument) }
                    .buttonStyle(QuietButton()).disabled(!hasDraft)
            }.font(.system(size: 10))
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("查看内容", selection: $detailTab) {
                ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            if detailTab == .preview { preview }
            else { history }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("预览版本", selection: $previewMode) {
                ForEach(PreviewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            if !store.loadErrors.isEmpty {
                errorText("配置读取失败，当前预览不代表有效配置。请重新读取出错文件后再使用远程 AI。")
            }
            Text(previewMode == .saved
                 ? "查看四份已保存配置组成的提示词。"
                 : "仅用当前文件的草稿替换预览；其他文件使用已保存版本。预览不会保存或联网。")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(promptPreview).font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .padding(10).frame(maxHeight: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
            VStack(alignment: .leading, spacing: 5) {
                Text("使用已保存的 AI 分享开关：Apple 来源\(appStore.cloudIncludeSystemData ? "已开启" : "已关闭")。")
                Text("此预览不联网，不包含日程、聊天或出生档案。离线回答不应用这些配置；启用远程 AI 时，配置内容会发送到你设置的服务。")
            }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(selectedDocument.rawValue) · \(selectedHistoryItems.count) 个历史版本")
                .font(.system(size: 11, weight: .medium))
            if let historyError = store.historyError { errorText(historyError) }
            if selectedHistoryItems.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 25)).foregroundStyle(Theme.jade)
                    Text("暂无历史版本").font(.system(size: 13, weight: .medium))
                    Text("保存修改后，可在这里查看保存前的内容。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(selectedHistoryItems) { item in
                            Button { selectedHistory = item } label: { historyRow(item) }.buttonStyle(.plain)
                        }
                    }
                }.frame(height: 145)
                if let item = selectedHistory {
                    HStack {
                        Text(item.isDefault ? "内置默认内容" : "所选版本正文").font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(item.content.count) 字符").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    ScrollView {
                        Text(item.content.isEmpty ? "（空白正文）" : item.content)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                    .padding(10).frame(maxHeight: .infinity)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
                    HStack {
                        Text("载入后需保存才会生效。")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Button("载入草稿") { requestReplacement(item.content, for: item.document, source: "历史版本") }
                            .buttonStyle(QuietButton()).font(.system(size: 11))
                    }
                } else {
                    Text("选择一个版本查看正文，再决定是否载入草稿。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func historyRow(_ item: AgentConfigHistory) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDefault ? "sparkles" : "clock.arrow.circlepath").foregroundStyle(Theme.jade)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.date.formatted(date: .abbreviated, time: .standard)).font(.system(size: 10, weight: .medium))
                Text("\(item.isDefault ? "默认" : "自定义") · \(String(item.revision.prefix(10)))")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if selectedHistory?.id == item.id { Image(systemName: "checkmark").foregroundStyle(Theme.jade) }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedHistory?.id == item.id ? Theme.softJade : Theme.card, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.error {
                ScrollView { errorText(error).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 38)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已保存版本 · \(String(store.revision(for: selectedDocument).prefix(12)))")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary)
                    if let feedback { Text(feedback).font(.system(size: 10)).foregroundStyle(Theme.jade) }
                }
                Spacer()
                Button("关闭") { requestClose() }.buttonStyle(QuietButton())
                Button("保存 \(selectedDocument.rawValue)") { saveSelected() }
                    .buttonStyle(JadeButton()).disabled(!hasDraft || validationError != nil || store.loadErrors[selectedDocument] != nil)
            }
        }
    }

    private func errorText(_ message: String) -> some View {
        Text(message).font(.system(size: 10)).foregroundStyle(Theme.vermilion)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func updateDraft(_ content: String, for document: AgentConfigDocument) {
        drafts[document] = content == store.value(for: document) ? nil : content
        feedback = nil
    }

    private func saveSelected() {
        guard let content = drafts[selectedDocument], validationError == nil else { return }
        if store.save(selectedDocument, content: content) {
            drafts[selectedDocument] = nil
            feedback = "已保存 \(selectedDocument.rawValue)，后续远程 AI 请求将使用此版本。"
        } else { feedback = nil }
    }

    private func requestClose() {
        if hasAnyDraft { pendingAction = .close }
        else { dismiss() }
    }

    private func requestReplacement(_ content: String, for document: AgentConfigDocument, source: String) {
        if let draft = drafts[document], draft != content {
            pendingAction = .replace(document, content: content, source: source)
        } else { loadDraft(content, for: document, source: source) }
    }

    private func loadDraft(_ content: String, for document: AgentConfigDocument, source: String) {
        updateDraft(content, for: document)
        previewMode = .draft
        feedback = content == store.value(for: document)
            ? "\(source)与已保存内容一致。"
            : "已将\(source)载入草稿，点击保存后生效。"
    }

    private func reload(_ document: AgentConfigDocument) {
        if store.reload(document) {
            drafts[document] = nil
            selectedHistory = nil
            feedback = "已从磁盘重新读取 \(document.rawValue)。"
        } else { feedback = nil }
    }

    private func perform(_ action: PendingAction) {
        switch action {
        case .close: dismiss()
        case .discard(let document):
            drafts[document] = nil
            feedback = "已丢弃 \(document.rawValue) 草稿。"
        case .reload(let document): reload(document)
        case .replace(let document, let content, let source): loadDraft(content, for: document, source: source)
        }
    }
}
