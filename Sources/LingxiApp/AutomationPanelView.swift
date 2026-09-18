import SwiftUI
import AppKit
import LingxiCore

struct AutomationPanelView: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var knowledge = KnowledgeLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var feedback: String?
    private var cliPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/lingxi").path }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("让自己的 Agent 使用灵性日历").font(.system(size: 24, design: .serif))
                    Text("本机 CLI · 结构化读取 · 分析与日程回写").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("允许本机 CLI 访问", isOn: Binding(get: { store.automationEnabled }, set: { store.setAutomationEnabled($0) }))
                            Text(store.automationStatus).font(.system(size: 12)).foregroundStyle(Theme.jade)
                            Text("仅这台 Mac 当前登录用户的进程可连接。关掉主窗口仍可使用；完全退出应用后 CLI 会提示重新打开。外部 Agent 只调用你授权的任务，应用不内置新的模型或后台 Agent。").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
                            Text(cliPath).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).lineLimit(nil)
                            HStack {
                                Button("复制测试命令") { copy("\"" + cliPath + "\"" + (store.isPreviewMode ? " --preview" : "") + " status") }
                                Button("复制 CLI 路径") { copy(cliPath) }
                            }.buttonStyle(QuietButton()).font(.system(size: 11))
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("公开的 CLI 接入 Skill").font(.system(size: 15, weight: .medium))
                            Text("这里提供的是灵性日历的公开接口说明，不是你的八字 PRO 私有技能。可交给自己的 Agent 学习查询与回写；私有资料仍留在原目录，通过下方逐集合授权的摘录接口查阅。").font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                            HStack {
                                Button("在 Finder 中查看 Skill") { if let url = Bundle.main.resourceURL?.appendingPathComponent("AgentSkill") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                                Button("复制 Skill 路径") { if let path = Bundle.main.resourceURL?.appendingPathComponent("AgentSkill/SKILL.md").path { copy(path) } }
                            }.buttonStyle(QuietButton()).font(.system(size: 11))
                            Text("本地日程和待办可读写；Apple 来源目前只读已选清单。提醒需在应用设置中启用系统通知。").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("私有知识集合").font(.system(size: 15, weight: .medium)); Spacer(); Button("添加文件夹", action: addFolder).buttonStyle(QuietButton()).font(.system(size: 11)) }
                            Text("新添加和从旧版迁移的集合默认关闭。启用后，只允许按用途搜索 Markdown／文本的小段摘录，不开放完整目录、整篇导出或 Python 源码。CLI 不返回本机路径，原件不打包、不上传。").font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                            if let error = knowledge.accessError {
                                Text(error).font(.system(size: 11)).foregroundStyle(Theme.vermilion)
                                Button("重建记录并关闭所有集合") { knowledge.recoverAccess(); feedback = "原记录已保留备份；所有集合保持关闭，请重新核对授权" }.buttonStyle(QuietButton()).font(.system(size: 11))
                            }
                            ForEach(knowledge.collections) { collection in
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack {
                                        Toggle(collection.name, isOn: Binding(get: { knowledge.accessError == nil && (knowledge.collections.first { $0.id == collection.id }?.isEnabled ?? false) }, set: { knowledge.setEnabled($0, for: collection.id) })).font(.system(size: 12, weight: .medium)).disabled(knowledge.accessError != nil)
                                        Spacer()
                                        Button("移除") { knowledge.remove(collection.id) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.vermilion)
                                    }
                                    Text(collection.directoryPath).font(.system(size: 10)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                                    HStack {
                                        Text("今日剩余 \(knowledge.remaining(for: collection)) 字").font(.system(size: 11)).foregroundStyle(Theme.jade)
                                        Spacer()
                                        Picker("每日额度", selection: Binding(get: { collection.dailyCharacterLimit }, set: { knowledge.setLimit($0, for: collection.id) })) {
                                            Text("1.2 万字").tag(12_000); Text("3 万字").tag(30_000); Text("6 万字").tag(60_000)
                                        }.font(.system(size: 11)).frame(width: 170)
                                        Button("重置今日") { knowledge.resetBudget(for: collection.id); feedback = "已由你重置该集合今日摘录额度" }.buttonStyle(.plain).font(.system(size: 10))
                                    }
                                    Text("北京时间每日零点更新 · 搜索、分页与重复读取都计入额度").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                                }.padding(12).background(Theme.paper, in: RoundedRectangle(cornerRadius: 10)).disabled(knowledge.accessError != nil)
                            }
                            Text("这是本机接口的访问约束，不是 DRM。已得到的摘录无法收回；有同一用户文件读取权限的 Agent 仍可能直接访问原件，请同时管理它的文件权限。").font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(4)
                        }
                    }
                    if !knowledge.audit.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("最近私有资料访问").font(.system(size: 15, weight: .medium))
                                Text("仅在本机保留最近 100 条用途、时间和字数，不记录摘录正文；CLI 不能读取这份记录或更改额度。").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                ForEach(Array(knowledge.audit.suffix(8).reversed())) { entry in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack { Text(knowledge.collectionName(entry.collectionID)); Spacer(); Text(entry.date, style: .time); Text("\(entry.characters) 字") }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                        Text(entry.purpose).font(.system(size: 11)).lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            HStack { if let feedback { Text(feedback).font(.system(size: 11)).foregroundStyle(Theme.jade) }; Spacer(); Button("完成") { dismiss() }.buttonStyle(JadeButton()) }
        }.padding(27).frame(width: 720, height: 740).background(Theme.paper)
    }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string); feedback = "已复制" }
    private func addFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "添加资料"
        if panel.runModal() == .OK, let url = panel.url {
            do { try knowledge.register(url); feedback = "已添加，默认关闭；请按需启用该集合" }
            catch { feedback = error.localizedDescription }
        }
    }
}
