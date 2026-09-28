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
                            Text("配套 Skill").font(.system(size: 15, weight: .medium))
                            Text("将 Skill 文件夹交给你使用的 Agent。它会学习如何查询确定的命盘与日程、按需查阅资料，并把结果保存回日笺。不同 Agent 的技能安装入口可能不同。").font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                            HStack {
                                Button("在 Finder 中查看 Skill") { if let url = Bundle.main.resourceURL?.appendingPathComponent("AgentSkill") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                                Button("复制 Skill 路径") { if let path = Bundle.main.resourceURL?.appendingPathComponent("AgentSkill/SKILL.md").path { copy(path) } }
                            }.buttonStyle(QuietButton()).font(.system(size: 11))
                            Text("本地日程和待办可读写；Apple 来源目前只读已选清单。提醒需在应用设置中启用系统通知。").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("知识与个人 Skill 资料").font(.system(size: 15, weight: .medium)); Spacer(); Button("添加文件夹", action: addFolder).buttonStyle(QuietButton()).font(.system(size: 11)) }
                            Text("内置排盘、旺衰分析流程、历法与日程准备说明。添加你的技能文件夹后，Agent 可按需读取其中的 Markdown、文本和 Python 源码；应用不会执行这些脚本，也不会把个人资料打进发布包。").font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                            ForEach(knowledge.paths, id: \.self) { path in
                                HStack { Text(path).font(.system(size: 10)).textSelection(.enabled); Spacer(); Button("移除") { knowledge.remove(path) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
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
            do { try knowledge.register(url); feedback = "已添加，可通过 knowledge search 查询" }
            catch { feedback = error.localizedDescription }
        }
    }
}
