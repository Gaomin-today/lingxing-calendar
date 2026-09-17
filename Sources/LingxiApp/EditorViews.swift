import SwiftUI
import AppKit
import LingxiCore

struct EventEditor: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var event: CalendarEvent
    @State private var destination = "local"
    @State private var deleting = false
    @State private var confirmConflict = false
    @State private var collisions: [EventOccurrence] = []
    @State private var preserveSystemAlarmLabel = false
    @State private var initialized = false
    @State private var rememberDestination = true
    @State private var showingConnections = false
    @State private var defaultBeforeConnections = "local"
    @State private var confirmTransfer = false
    @State private var feedback: String?
    private var exists: Bool { event.isExternal || store.events.contains { $0.id == event.id } }
    private var readOnly: Bool { event.externalReadOnly == true || store.isPendingTransferDestination(event) }
    private var pendingTransfer: CalendarEvent? { store.pendingTransfer(for: event) }
    private var movingLocal: Bool { exists && !event.isExternal && destination != "local" }
    private var availableDestinations: [SystemCalendarChoice] { store.destinationCalendars.filter { $0.isReminder == event.isTask } }
    private var destinationAvailable: Bool { event.isExternal || destination == "local" || availableDestinations.contains { $0.id == destination } }
    private var valid: Bool { pendingTransfer != nil || (!event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (event.isTask || event.end > event.start) && !readOnly && destinationAvailable && !(movingLocal && event.isTask && event.repeatRule != .none)) }
    private var saveLabel: String {
        if pendingTransfer != nil { return "完成本地副本整理" }
        if movingLocal { return event.isTask ? "转入 Apple 提醒事项" : "转入 Apple 日历" }
        return event.isExternal || destination != "local" ? "保存到 Apple" : "保存到本地"
    }
    private var checkKey: String { "\(event.start)-\(event.end)-\(event.isAllDay)-\(event.isTask)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(readOnly ? "查看安排" : (exists ? "编辑\(event.isTask ? "待办" : "日程")" : "给日子一个安排")).font(.system(size: 23, weight: .medium, design: .serif)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    HStack { Text("北京时间 · 历史按当地钟表").font(.system(size: 10)).foregroundStyle(Theme.secondary); Spacer(); Pill(text: event.isExternal ? event.sourceLabel : store.destinationLabel(destination, isTask: event.isTask)) }
                    if readOnly { Text(store.isPendingTransferDestination(event) ? "请先打开本地副本完成转入整理，再编辑这条 Apple 日程。" : (event.externalReadOnlyReason ?? "这个来源只可查看。")).font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
                    TextField("想做些什么？", text: $event.title).font(.system(size: 20)).textFieldStyle(.plain).padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).accessibilityLabel("日程标题").disabled(readOnly || pendingTransfer != nil)
                    VStack(alignment: .leading, spacing: 16) {
                        if !exists {
                            Picker("类型", selection: $event.isTask) { Text("日程").tag(false); Text("待办").tag(true) }.pickerStyle(.segmented)
                        }
                        if !event.isExternal {
                            Picker("保存到", selection: $destination) {
                                Text("仅灵性日历（本地，不写入 Apple）").tag("local")
                                ForEach(availableDestinations) { choice in Text("\(event.isTask ? "Apple 提醒事项" : "Apple 日历") · \(choice.title) · \(choice.sourceTitle)").tag(choice.id) }
                                if destination != "local" && !destinationAvailable { Text("原 Apple 保存位置不可用，请重新选择").tag(destination) }
                            }
                            if destination == "local" {
                                Text("只保存在灵性日历，不会出现在 Apple \(event.isTask ? "提醒事项" : "日历")中。连接后可在这里选择 Apple 保存位置。").font(.system(size: 11)).foregroundStyle(Theme.vermilion)
                            } else if movingLocal {
                                Text("确认转入后，由 Apple 保存和同步这条\(event.isTask ? "待办" : "日程")；本地副本在写入成功后移除。重复日程会转入整个系列。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            } else {
                                Text("保存时直接写入所选 Apple 来源，之后由该账户同步。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            }
                            if !destinationAvailable { Text("原保存位置已断开或不可写，尚未改存到本地。请连接或选择其他位置。").font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
                            if movingLocal && event.isTask && event.repeatRule != .none { Text("重复本地待办暂不支持转入，请在 Apple 提醒事项中设置重复规则。").font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
                            Toggle("将此位置用于以后新建的\(event.isTask ? "待办" : "日程")（含阿灵）", isOn: $rememberDestination).toggleStyle(.checkbox).font(.system(size: 10))
                            Button("连接 / 管理 Apple 保存位置") { defaultBeforeConnections = store.defaultDestination(isTask: event.isTask); showingConnections = true }.buttonStyle(QuietButton()).font(.system(size: 11))
                        }
                        if event.isTask { taskDateFields } else { eventDateFields }
                        if !event.isTask {
                            TextField("地点或会议链接（可选）", text: Binding(get: { event.location ?? "" }, set: { event.location = $0.isEmpty ? nil : $0 })).textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            if event.isExternal {
                                Text(event.externalRecurring == true ? "重复规则由原来源维护" : "不重复").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            } else {
                                Picker("重复", selection: $event.repeatRule) { ForEach(EventRepeat.allCases) { rule in Text(rule.label).tag(rule) } }.disabled(event.isTask && (!event.hasDueDate || destination != "local"))
                            }
                            reminderPicker.disabled(event.isTask && (!event.hasDueDate || event.taskDueHasTime == false))
                        }.font(.system(size: 12))
                        if !event.isExternal && event.isTask && destination != "local" { Text("系统重复待办的完整规则请在 Apple 提醒事项中设置。").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                        if event.isExternal { Text("未更改提醒选项时保留原有系统提醒；绝对时间、多重或位置提醒请在 Apple 应用中管理。").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                        if event.isTask && event.hasDueDate && event.taskDueHasTime == false { Text("只有截止日期的待办不单独发阿灵通知；需要通知时请启用具体时间。").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                        if event.externalRecurring == true { Text("这是 Apple 重复日程，保存或删除仅影响本次；完整重复规则保留在原来源中。").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                        else if event.repeatRule != .none { Text("本地重复项目的修改或删除应用到整个系列；重复待办完成后整组停止提醒。").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                        VStack(alignment: .leading, spacing: 8) { Text("备注").font(.system(size: 11)).foregroundStyle(Theme.secondary); TextEditor(text: $event.notes).font(.system(size: 12)).scrollContentBackground(.hidden).padding(8).frame(height: 70).background(Theme.card, in: RoundedRectangle(cornerRadius: 9)).accessibilityLabel("备注") }
                    }.disabled(readOnly || pendingTransfer != nil)
                    if let pendingTransfer {
                        Text("已写入\(pendingTransfer.sourceLabel)，正在等待移除本地副本。点击下方按钮仅完成本地整理，不会重复创建 Apple 日程。转入内容暂不可再修改。").font(.system(size: 11)).foregroundStyle(Theme.vermilion)
                    }
                    if !collisions.isEmpty && !event.isTask {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("与 \(collisions.count) 项安排重叠", systemImage: "exclamationmark.circle").font(.system(size: 11, weight: .medium))
                            ForEach(collisions.prefix(3)) { item in Text("\(DateText.time(item.start)) · \(item.event.title) · \(item.event.sourceLabel)").font(.system(size: 10)) }
                            Text("检查本次时段与已选来源；不预判整个重复系列。").font(.system(size: 9))
                        }.foregroundStyle(Theme.vermilion).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.vermilion.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let feedback { Text(feedback).font(.system(size: 11)).foregroundStyle(Theme.vermilion).fixedSize(horizontal: false, vertical: true) }
                }.padding(.trailing, 4)
            }
            HStack {
                if !event.title.isEmpty { Button("问问阿灵") { store.askAboutEvent(event) }.buttonStyle(.plain).foregroundStyle(Theme.jade) }
                if exists && !readOnly && pendingTransfer == nil { Button("删除", role: .destructive) { deleting = true }.buttonStyle(.plain).foregroundStyle(Theme.vermilion) }
                Spacer(); Button(readOnly ? "关闭" : "取消") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                if !readOnly { Button(saveLabel) { prepareSave() }.buttonStyle(JadeButton()).disabled(!valid).keyboardShortcut(.defaultAction) }
            }.font(.system(size: 12))
        }.padding(26).frame(width: 550, height: 730).background(Theme.paper).foregroundStyle(Theme.ink).preferredColorScheme(.light)
        .task(id: checkKey) { collisions = store.conflicts(for: event) }
        .onAppear {
            guard !initialized else { return }; initialized = true
            preserveSystemAlarmLabel = event.isExternal && event.reminderMinutes == nil
            destination = pendingTransfer?.externalCalendarID ?? (exists ? "local" : store.defaultDestination(isTask: event.isTask))
            rememberDestination = !exists
        }
        .onChange(of: destination) { _, target in if !exists && event.isTask && target != "local" { event.repeatRule = .none } }
        .onChange(of: event.isTask) { _, isTask in
            guard !exists else { return }; destination = store.defaultDestination(isTask: isTask)
            if isTask { event.taskHasDueDate = false; event.taskDueHasTime = false; event.isAllDay = false; event.reminderMinutes = nil; event.repeatRule = .none }
            else { event.end = event.start.addingTimeInterval(3600); event.reminderMinutes = 15 }
        }
        .onChange(of: event.isAllDay) { _, allDay in if allDay && !event.isTask { event.start = store.calendar.gregorian.startOfDay(for: event.start); event.end = store.calendar.gregorian.date(byAdding: .day, value: 1, to: event.start)! } }
        .onChange(of: event.start) { old, new in if !event.isTask && event.end <= new { event.end = new.addingTimeInterval(max(3600, event.end.timeIntervalSince(old))) } }
        .confirmationDialog(event.isExternal ? "从「\(event.externalCalendarTitle ?? "系统来源")」删除？重复日程仅删除本次。" : "删除「\(event.title)」？本地重复项目将删除整个系列。", isPresented: $deleting) {
            Button("删除", role: .destructive) { if store.delete(event) { dismiss() } else { feedback = store.status } }
        }
        .confirmationDialog("这个时段与已有安排重叠，仍要保存吗？", isPresented: $confirmConflict) { Button("仍然保存") { commit() } }
        .confirmationDialog("转入\(store.destinationLabel(destination, isTask: event.isTask))？成功后移除本地副本，后续修改写回 Apple。", isPresented: $confirmTransfer) { Button("确认转入") { checkConflictsAndSave() } }
        .sheet(isPresented: $showingConnections, onDismiss: {
            let chosen = store.defaultDestination(isTask: event.isTask)
            if !exists && chosen != defaultBeforeConnections { destination = chosen }
        }) { SystemConnectionsView(store: store, service: store.system) }
    }
    private var eventDateFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("全天", isOn: $event.isAllDay).toggleStyle(.checkbox)
            DatePicker("开始", selection: $event.start, displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute]).environment(\.timeZone, CalendarEngine.timeZone)
            DatePicker(event.isAllDay ? "结束（不含当天）" : "结束", selection: $event.end, displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute]).environment(\.timeZone, CalendarEngine.timeZone)
            if event.end <= event.start { Text("结束时间需要晚于开始时间。").font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
        }
    }
    private var taskDateFields: some View {
        VStack(alignment: .leading, spacing: 13) {
            Toggle("设置截止日期", isOn: Binding(get: { event.hasDueDate }, set: { event.taskHasDueDate = $0; if !$0 { event.reminderMinutes = nil; event.repeatRule = .none } })).toggleStyle(.checkbox)
            if event.hasDueDate {
                Toggle("设置具体时间", isOn: Binding(get: { event.taskDueHasTime != false }, set: { event.taskDueHasTime = $0; if !$0 { event.reminderMinutes = nil } })).toggleStyle(.checkbox)
                DatePicker("截止", selection: $event.start, displayedComponents: event.taskDueHasTime == false ? [.date] : [.date, .hourAndMinute]).environment(\.timeZone, CalendarEngine.timeZone)
            }
            Text("待办不会占用空闲时段，可以之后通过“安排时间”创建一段专注日程。").font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }
    }
    private var reminderPicker: some View {
        Picker("提醒", selection: Binding(get: { event.reminderMinutes ?? -1 }, set: { event.reminderMinutes = $0 == -1 ? nil : $0 })) {
            Text(preserveSystemAlarmLabel ? "保留系统设置" : "不提醒").tag(-1); Text("准时").tag(0); Text("提前 5 分钟").tag(5); Text("提前 10 分钟").tag(10); Text("提前 15 分钟").tag(15); Text("提前 30 分钟").tag(30); Text("提前 1 小时").tag(60); Text("提前 1 天").tag(1440)
            if let minutes = event.reminderMinutes, ![0, 5, 10, 15, 30, 60, 1440].contains(minutes) { Text("提前 \(minutes) 分钟").tag(minutes) }
        }
    }
    private func prepareSave() {
        if pendingTransfer != nil { commit(); return }
        event.title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if event.isTask {
            if event.hasDueDate && event.taskDueHasTime == false { event.start = store.calendar.gregorian.startOfDay(for: event.start) }
            event.end = event.start; event.isAllDay = false
            if !event.isExternal && (!event.hasDueDate || event.taskDueHasTime == false) { event.reminderMinutes = nil }
        } else if event.isAllDay {
            event.start = store.calendar.gregorian.startOfDay(for: event.start); event.end = store.calendar.gregorian.startOfDay(for: event.end)
            if event.end <= event.start { event.end = store.calendar.gregorian.date(byAdding: .day, value: 1, to: event.start)! }
        }
        if movingLocal { confirmTransfer = true } else { checkConflictsAndSave() }
    }
    private func checkConflictsAndSave() {
        collisions = store.conflicts(for: event)
        if collisions.isEmpty { commit() } else { confirmConflict = true }
    }
    private func commit() {
        if store.save(event, toCalendarID: destination == "local" ? nil : destination) {
            if !event.isExternal && rememberDestination { store.setDefaultDestination(destination, isTask: event.isTask) }
            if !event.isTask || event.hasDueDate { store.select(event.start) }
            dismiss()
        } else { feedback = store.status }
    }
}

struct ChatView: View {
    @ObservedObject var store: AppStore
    var isSheet = false
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var editingDraft: CalendarEvent?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SpiritView(size: 46)
                VStack(alignment: .leading, spacing: 5) { Text("阿灵").font(.system(size: 18, weight: .medium, design: .serif)); Text(store.cloudEnabled ? "AI 对话 · 日程指令在本地处理" : "本地助手 · 无需联网").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                Spacer()
                if isSheet { Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            }.padding(20)
            HStack { Image(systemName: "calendar"); Text("正在聊：\(DateText.day(store.selectedDate))"); Spacer(); Text("北京时间") }.font(.system(size: 10)).foregroundStyle(Theme.jade).padding(.horizontal, 20).padding(.vertical, 10).background(Theme.softJade.opacity(0.7))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(store.messages) { message in
                            HStack {
                                if message.isUser { Spacer(minLength: 40) }
                                Text(message.text).font(.system(size: 12)).lineSpacing(5).textSelection(.enabled).padding(14).background(message.isUser ? Theme.softJade : Theme.card, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.line.opacity(0.55), lineWidth: 1))
                                if !message.isUser { Spacer(minLength: 20) }
                            }.id(message.id)
                        }
                        if let draft = store.draft {
                            Card { VStack(alignment: .leading, spacing: 12) {
                                Pill(text: "待确认日程")
                                Text(draft.title).font(.system(size: 15, weight: .medium))
                                Text(DateText.full(draft.start)).font(.system(size: 12))
                                Text("保存到：\(store.destinationLabel(store.defaultDestination(isTask: false), isTask: false))").font(.system(size: 10)).foregroundStyle(Theme.jade)
                                if store.defaultDestination(isTask: false) == "local" { Text("本地日程不会写入 Apple；可点“修改”选择 Apple 保存位置。").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                                Text("\(draft.durationMinutes) 分钟 · \(EventRepeat(rawValue: draft.repeatRule)?.label ?? "不重复") · \(draft.reminderMinutes < 0 ? "不提醒" : "提前 \(draft.reminderMinutes) 分钟提醒")").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                HStack { Button("加入日历") { if let conflict = store.confirmDraft() { editingDraft = conflict } }.buttonStyle(JadeButton()); Button("修改") { editingDraft = CalendarEvent(title: draft.title, start: draft.start, end: draft.start.addingTimeInterval(Double(draft.durationMinutes * 60)), notes: draft.notes, repeatRule: EventRepeat(rawValue: draft.repeatRule) ?? .none, reminderMinutes: draft.reminderMinutes < 0 ? nil : draft.reminderMinutes) }.buttonStyle(QuietButton()); Button("取消") { store.draft = nil }.buttonStyle(.plain).font(.system(size: 11)) }
                            } }.id("draft")
                        }
                        if store.isThinking { HStack { ProgressView().controlSize(.small); Text("阿灵正在想一想…").font(.system(size: 11)).foregroundStyle(Theme.secondary) }.id("thinking") }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(20)
                }.onChange(of: store.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onChange(of: store.draft != nil) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onChange(of: store.isThinking) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            HStack(spacing: 8) {
                Button("明天下午三点开会") { input = "提醒我明天下午三点开会" }
                Button("聊聊当天安排") { store.send("聊聊这一天的安排，给我一些建议") }
            }.font(.system(size: 10)).buttonStyle(QuietButton()).padding(.horizontal, 14).padding(.bottom, 10)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("说说你的安排，或此刻的心情…", text: $input, axis: .vertical).lineLimit(1...4).textFieldStyle(.plain).font(.system(size: 12)).padding(13).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).onSubmit(send)
                Button(action: send) { Image(systemName: "arrow.up").font(.system(size: 15, weight: .medium)) }.buttonStyle(JadeButton()).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isThinking).accessibilityLabel("发送")
            }.padding(.horizontal, 20)
            Text("民俗与自我探索，不承诺预测结果").font(.system(size: 9)).foregroundStyle(Theme.secondary).padding(12)
        }.frame(width: 470, height: 650).background(Theme.paper).foregroundStyle(Theme.ink).preferredColorScheme(.light)
            .sheet(item: $editingDraft, onDismiss: { store.draft = nil }) { EventEditor(store: store, event: $0) }
    }
    private func send() { let message = input; input = ""; store.send(message) }
}

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var feedback: String?
    @State private var cloudEnabled = false
    @State private var endpoint = ""
    @State private var modelName = ""
    @State private var includeSystemData = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("让陪伴恰到好处").font(.system(size: 24, weight: .medium, design: .serif)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Card { VStack(alignment: .leading, spacing: 12) {
                        Text("桌面与提醒").font(.system(size: 13, weight: .semibold))
                        Toggle("显示桌面阿灵", isOn: Binding(get: { store.petVisible }, set: { _ in store.togglePet() }))
                        Text(store.notificationStatus).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        HStack { Button("启用 / 刷新提醒") { Task { await store.refreshNotifications(requestPermission: true) } }; Button("测试通知") { Task { do { try await store.notifications.sendTest(); feedback = "已提交测试提醒，请留意系统通知。" } catch { feedback = error.localizedDescription } } }.disabled(store.isPreviewMode); Button("系统通知设置") { if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) } } }.buttonStyle(QuietButton()).font(.system(size: 11))
                        Text("为本地记录安排未来 30 天内最早的 52 条常规提醒，并为稍后提醒保留容量，总计最多 60 条。通知支持稍后 10 分钟／1 小时、完成待办。退出后仅已安排的提醒有效；Apple 来源由系统应用负责通知。").font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    } }
                    Card { VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("可选 AI 对话").font(.system(size: 13, weight: .semibold)); Spacer(); Pill(text: "自行配置") }
                        Toggle("启用远程 AI 对话", isOn: $cloudEnabled)
                        Toggle("向 AI 提供已选 Apple 来源的事项标题", isOn: $includeSystemData)
                        Text("使用兼容 Chat Completions 的服务。发送消息时，会将最近 12 条聊天、选中日期和本地日程标题发送至你填写的服务。仅开启上方选项时才提供系统来源上下文。日程写入仍在本地确认。").font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        TextField("完整 HTTPS 地址，例如 https://你的服务/v1/chat/completions", text: $endpoint).textFieldStyle(.roundedBorder)
                        TextField("模型名称", text: $modelName).textFieldStyle(.roundedBorder)
                        SecureField("API 密钥（留空保留已有值）", text: $key).textFieldStyle(.roundedBorder)
                        HStack { Text("密钥保存在 macOS 钥匙串").font(.system(size: 10)).foregroundStyle(Theme.secondary); Spacer(); Button("删除密钥") { KeychainCredential.delete(); key = ""; feedback = "已删除保存的密钥" }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.vermilion) }
                    } }
                    Card { VStack(alignment: .leading, spacing: 10) {
                        Text("数据与来源").font(.system(size: 13, weight: .semibold))
                        Text("本地日程存于这台 Mac；已连接的 Apple 来源由系统账户同步。聊天记录只在本次运行中保留。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        if let error = store.storageError { Text(error).font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
                        Button("在 Finder 中查看本地数据") { NSWorkspace.shared.activateFileViewerSelecting([store.repository.fileURL]) }.buttonStyle(QuietButton()).font(.system(size: 11))
                        Text("民用月历采用 Asia/Shanghai 时区，农历年干支正月初一换年、日干支零点换日。节气与四柱支持 1901–2099 年；黄历采用固定版本的传统规则，详见“历法与资料说明”。").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    } }
                }
            }
            HStack { if let feedback { Text(feedback).font(.system(size: 11)).foregroundStyle(Theme.vermilion) }; Spacer(); Button("保存设置") { do { try store.saveSettings(enabled: cloudEnabled, endpoint: endpoint, model: modelName, key: key); store.cloudIncludeSystemData = includeSystemData; UserDefaults.standard.set(includeSystemData, forKey: "cloudIncludeSystemData"); dismiss() } catch { feedback = error.localizedDescription } }.buttonStyle(JadeButton()) }
        }.padding(28).frame(width: 570, height: 740).background(Theme.paper).foregroundStyle(Theme.ink).preferredColorScheme(.light)
        .onAppear { cloudEnabled = store.cloudEnabled; endpoint = store.endpoint; modelName = store.modelName; includeSystemData = store.cloudIncludeSystemData }
    }
}

struct SourcesView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("历法与资料说明").font(.system(size: 24, weight: .medium, design: .serif)); Spacer(); Button("关闭") { dismiss() }.buttonStyle(QuietButton()) }
            ScrollView { VStack(alignment: .leading, spacing: 20) {
                section("民用日历口径", "公历与农历由系统 Foundation 中国历法计算，使用 Asia/Shanghai 时区（现代为 UTC+8，历史夏令时随时区规则）。闰月明确标记。月历上的农历年干支按正月初一换年，日干支采用零点换日。")
                section("月历上的节气", "支持 1901–2099 年全部二十四节气，与四柱共用本地太阳黄经算法。月历在节气所在的民用日期显示标签，不表示当天零点已经交节。2025–2027 年共 72 个节气日期已逐项匹配香港天文台年表；其他年份为算法计算值。")
                Link("香港天文台 · 公历与农历对照表 ↗", destination: URL(string: "https://www.hko.gov.hk/sc/gts/time/conversion.htm")!).font(.system(size: 12)).foregroundStyle(Theme.jade)
                section("四柱排盘口径", "支持 1901–2099 年。立春交接时换年，十二节交接时换月；按所选当地钟表时间定日和时柱，不校正真太阳时。档案可选零点或 23 点换日；两种口径的晚子时时干均从次日日干推起，与 lunar 的 sect=2／sect=1 对应。四柱年柱可能与月历农历年干支不同。")
                section("交节算法与精度", "采用 lunar-swift 1.1.8 的太阳视黄经与 ΔT 算法，代码版本固定并保留 MIT 许可。已交叉核对香港天文台六个分钟级参考时刻，不能据此声称所有年份都有秒级精度；靠近交节前后 2 分钟会提示核对。")
                Link("lunar-swift · 算法与许可 ↗", destination: URL(string: "https://github.com/6tail/lunar-swift/tree/a7ec0e9b29f84a5d98b09b9ffd31145f17470d56")!).font(.system(size: 12)).foregroundStyle(Theme.jade)
                section("出生档案与不确定性", "出生档案独立保存在本机，不进入阿灵的云端聊天上下文。未知时刻不补造时柱；生日遇到交节或所选换日边界时，列出可能命盘并暂停单一日运解读。时钟回拨产生重复时间时取首次，并提示歧义。")
                section("命盘规则表", "藏干、十神、纳音、十二长生、旬空使用固定的 lunar-swift 1.1.8 规则表。星运按日干对各支，自坐按本柱天干对本支；这些分类不能单独判定旺衰、喜用或吉凶。未知时柱保持空缺。")
                section("起运、大运与流月", "起运采用该库 Yun sect 2 分钟法，顺逆需要用户明确选择传统排运参数。交运是传统规则的计算值，按真实计算时刻划分连续十年区间；流年在立春瞬间切换，流月在十二节瞬间切换。不是公历整年整月，也不在一月一日统一换运。")
                section("个人日历解读", "以日主为基准核对流年、流月、流日十神，结合月令本气、透干与藏干根气线索。用户选择的身强／身弱只作为解释假设，不是程序判断的结论；尚未综合调候、格局、大运等条件认定喜用。行动建议是现代生活转译，不提供综合吉凶分。")
                section("传统关系依据", "十神、天干五合、地支六合／六冲／六害，参考《三命通会》卷二、卷五，并保留对应柱位。扶抑思路参考卷七；合不直接代表吉，冲不直接代表凶。原典是传统思想资料，不构成预测效果的验证。")
                Link("《三命通会》· 卷二 ↗", destination: URL(string: "https://zh.wikisource.org/wiki/三命通會_(四庫全書本)/卷02")!).font(.system(size: 12)).foregroundStyle(Theme.jade)
                section("日黄历与时辰", "日时宜忌、值神、冲煞、神位和九星来自 lunar-swift 1.1.8 的传统表。日黄历零点换日；月建和年／月九星按库的固定 UTC+8 交节日期切换，历史夏令时期间可与日历当地钟表的节气日期不同。时辰按晚子时 23:00 换日，分成早子、晚子等 13 个时段。黄历按日期切换，排盘按交节瞬间切换，两种口径分别保留。")
                section("黄历字段的含义", "宜忌、黄道／黑道和吉／凶是固定版本的传统分类，不是统一历书结论或事件成功率。日常行动建议另按事项类型生成；个人解读另用出生盘与参考盘。三者不互相冒充依据。")
                section("民俗资料", "目录目前有 24 条节日与神诞，每条保留来源、地域和简短自编说明。新增资料核对中国非遗网、地方政府、香港华人庙宇委员会与香港佛教联合会年历。不同传统可能采用不同纪念日或名称；闰月不自动重复。目录不是法定放假表，纪念日订阅提醒尚未实现。")
                Link("香港华人庙宇委员会 · 节诞原表 ↗", destination: URL(string: "https://www.ctc.org.hk/zh-hans/festival/")!).font(.system(size: 12)).foregroundStyle(Theme.jade)
                Link("香港佛教联合会 · 2025 年历与纪念日期表 ↗", destination: URL(string: "https://www.hkbuddhist.org/editor_upload_image/file/calendar2025.pdf")!).font(.system(size: 12)).foregroundStyle(Theme.jade)
                section("建议与占卜", "民俗与个人解读用于文化体验和自我探索。阿灵可结合日程陪你梳理心情与选择；正式卦象演算尚未接入。")
                section("提醒与重复", "本地支持一次性、每日、每周日程；修改或删除针对整个系列，重复待办完成也会结束整个系列。Apple 已有重复日程只操作本次。通知最多 52 条常规提醒，连同稍后提醒不超过 60 条，运行期间补充。")
            } }
        }.padding(30).frame(width: 580, height: 600).background(Theme.paper).foregroundStyle(Theme.ink)
    }
    private func section(_ title: String, _ body: String) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 14, weight: .medium)); Text(body).font(.system(size: 12)).lineSpacing(5).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) } }
}
