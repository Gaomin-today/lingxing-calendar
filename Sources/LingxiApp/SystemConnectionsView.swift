import SwiftUI
import AppKit

struct SystemConnectionsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var service: SystemCalendarService
    @Environment(\.dismiss) private var dismiss
    @State private var requesting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("把真实的安排连进来").font(.system(size: 24, weight: .medium, design: .serif)); Spacer(); Button("完成") { dismiss() }.buttonStyle(QuietButton()) }
            Text("先连接 Apple，再选择新建事项的默认保存位置。下方勾选决定显示哪些来源；仅连接不会自动搬移原来的本地日程。").font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sourceSection(isReminder: false)
                    sourceSection(isReminder: true)
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("显示、写入与提醒", systemImage: "info.circle").font(.system(size: 12, weight: .medium))
                            Text("选择 Apple 默认位置后，新建日程和阿灵草稿会写入该来源。已有本地日程需打开编辑器，在“保存到”选择 Apple 后确认转入。已有 Apple 日程直接写回原来源；重复日程只修改或删除本次。").font(.system(size: 11)).lineSpacing(4)
                            Text("Apple 来源的提醒交由系统日历／提醒事项处理；阿灵只为本地记录另发通知。系统日历不会复制到本地日程文件。").font(.system(size: 11)).lineSpacing(4)
                            Text("macOS 读取日历需要申请“完整访问”。应用只在你明确保存、删除或完成时写入。").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                    }
                    if let error = store.systemSyncMessage ?? service.lastError { Text(error).font(.system(size: 11)).foregroundStyle(Theme.vermilion).textSelection(.enabled) }
                }
            }
            HStack {
                Text(store.systemLastRefresh.map { "最近检查 \(DateText.time($0))" } ?? "尚未检查系统来源").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                if store.systemLoading || requesting { ProgressView().controlSize(.small) }
                Button("刷新来源") { Task { await store.reloadSystemData() } }.buttonStyle(QuietButton()).disabled(store.systemLoading)
                Button("系统隐私设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }.buttonStyle(QuietButton())
            }.font(.system(size: 11))
        }.padding(28).frame(width: 620, height: 720).background(Theme.paper).foregroundStyle(Theme.ink).preferredColorScheme(.light)
        .task { await store.reloadSystemData() }
    }
    private func sourceSection(isReminder: Bool) -> some View {
        let allowed = isReminder ? service.canReadReminders : service.canReadEvents
        let choices = service.calendars.filter { $0.isReminder == isReminder }
        return Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label(isReminder ? "Apple 提醒事项" : "Apple 日历", systemImage: isReminder ? "checklist" : "calendar").font(.system(size: 14, weight: .medium))
                    Spacer(); Pill(text: isReminder ? service.reminderPermission : service.eventPermission)
                }
                if !allowed {
                    Text(isReminder ? "把待办清单带进来，保留截止日期与完成状态。" : "在月、周、日视图中查看工作和生活安排，并检查冲突。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Button(isReminder ? "连接提醒事项" : "连接 Apple 日历") {
                        requesting = true
                        Task {
                            if isReminder { await service.requestRemindersAccess() } else { await service.requestEventsAccess() }
                            await store.reloadSystemData(); requesting = false
                        }
                    }.buttonStyle(JadeButton()).disabled(requesting)
                } else if choices.isEmpty {
                    Text("系统中暂未找到\(isReminder ? "清单" : "日历")，可先在 Apple 应用中配置账户。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                } else {
                    let currentDefault = store.defaultDestination(isTask: isReminder)
                    let writable = choices.filter(\.isWritable)
                    Picker("新建\(isReminder ? "待办" : "日程")默认保存到", selection: Binding(get: { store.defaultDestination(isTask: isReminder) }, set: { store.setDefaultDestination($0, isTask: isReminder) })) {
                        Text("仅灵性日历（本地，不写入 Apple）").tag("local")
                        ForEach(writable) { choice in Text("\(choice.title) · \(choice.sourceTitle)").tag(choice.id) }
                        if currentDefault != "local" && !writable.contains(where: { $0.id == currentDefault }) { Text("原保存位置不可用，请重新选择").tag(currentDefault) }
                    }.font(.system(size: 11))
                    Text(currentDefault == "local" ? "当前新建只存本地。要出现在 Apple 应用中，请在上方选择一个日历或清单。" : "之后的新建与阿灵草稿使用此位置；已有本地事项不会自动迁移。").font(.system(size: 10)).foregroundStyle(currentDefault == "local" ? Theme.vermilion : Theme.secondary)
                    Divider()
                    Text("在灵性日历中显示").font(.system(size: 11, weight: .medium))
                    ForEach(choices) { choice in
                        HStack(spacing: 10) {
                            Toggle(isOn: Binding(get: { isReminder ? store.selectedReminderIDs.contains(choice.id) : store.selectedCalendarIDs.contains(choice.id) }, set: { store.setSource(choice, selected: $0) })) {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(hex: choice.colorHex)).frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 3) { Text(choice.title).font(.system(size: 12)); Text(choice.sourceTitle).font(.system(size: 9)).foregroundStyle(Theme.secondary) }
                                }
                            }.toggleStyle(.checkbox)
                            Spacer(); Text(choice.isWritable ? "可写" : "只读").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                        }.padding(.vertical, 3)
                    }
                }
            }
        }
    }
}
