import SwiftUI
import LingxiCore

struct TaskListView: View {
    @ObservedObject var store: AppStore
    @State private var search = ""
    @State private var showingCompleted = false
    @State private var source = "all"
    private var allTasks: [CalendarEvent] {
        store.allEvents.filter { $0.isTask && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) && (source == "all" || source == "local" && !$0.isExternal || source == "apple" && $0.isExternal) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) { Text("一件一件，慢慢完成").font(.system(size: 25, weight: .medium, design: .serif)); Text("待办有自己的节奏，安排时间后再放进日历。").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                    Spacer(); Button { store.newEvent(isTask: true) } label: { Label("添加待办", systemImage: "plus") }.buttonStyle(JadeButton())
                }
                HStack { TextField("查找待办", text: $search).textFieldStyle(.roundedBorder); Picker("来源", selection: $source) { Text("全部来源").tag("all"); Text("本地").tag("local"); Text("Apple 提醒事项").tag("apple") }.frame(width: 175) }
                if allTasks.isEmpty {
                    Card { VStack(alignment: .leading, spacing: 12) { Text(search.isEmpty ? "还没有待办，记下一件想完成的事吧。" : "没有匹配的待办。").font(.system(size: 13)); Button("连接 Apple 提醒事项") { store.showingConnections = true }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.jade) }.padding(.vertical, 24) }
                }
                taskGroup("已逾期", tasks: pending.filter { $0.hasDueDate && dueIsPast($0) }, color: Theme.vermilion)
                taskGroup("今天", tasks: pending.filter { $0.hasDueDate && !dueIsPast($0) && store.calendar.gregorian.isDateInToday($0.start) })
                taskGroup("接下来", tasks: pending.filter { $0.hasDueDate && !dueIsPast($0) && !store.calendar.gregorian.isDateInToday($0.start) })
                taskGroup("不设期限", tasks: pending.filter { !$0.hasDueDate })
                if allTasks.contains(where: { $0.isCompleted }) {
                    DisclosureGroup("已完成 · \(allTasks.filter { $0.isCompleted }.count)", isExpanded: $showingCompleted) {
                        VStack(spacing: 9) { ForEach(allTasks.filter { $0.isCompleted }.prefix(100)) { task in TaskItemRow(store: store, task: task) } }.padding(.top, 12)
                    }.font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }.padding(26)
        }
    }
    private var pending: [CalendarEvent] { allTasks.filter { !$0.isCompleted }.sorted { $0.start < $1.start } }
    private func dueIsPast(_ task: CalendarEvent) -> Bool {
        if task.taskDueHasTime == false { return store.calendar.gregorian.startOfDay(for: task.start) < store.calendar.gregorian.startOfDay(for: Date()) }
        return task.start < Date()
    }
    @ViewBuilder private func taskGroup(_ title: String, tasks: [CalendarEvent], color: Color = Theme.jade) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text(title).font(.system(size: 12, weight: .medium)); Text("\(tasks.count)").font(.system(size: 10)).foregroundStyle(Theme.secondary) }.foregroundStyle(color)
                ForEach(tasks) { task in TaskItemRow(store: store, task: task) }
            }
        }
    }
}

private struct TaskItemRow: View {
    @ObservedObject var store: AppStore
    let task: CalendarEvent
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Button { store.toggleCompleted(task) } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20)).foregroundStyle(Theme.jade).frame(width: 32, height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(task.externalReadOnly == true).accessibilityLabel(task.isCompleted ? "恢复待办 \(task.title)" : "完成待办 \(task.title)")
                Button { store.editorEvent = task } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(task.title).font(.system(size: 13, weight: .medium)).strikethrough(task.isCompleted).foregroundStyle(task.isCompleted ? Theme.secondary : Theme.ink)
                        HStack(spacing: 8) {
                            Text(task.hasDueDate ? (task.taskDueHasTime == false ? DateText.day(task.start) : DateText.full(task.start)) : "不设截止日期")
                            Text("·"); Text(task.sourceLabel)
                        }.font(.system(size: 9)).foregroundStyle(Theme.secondary)
                        if task.externalReadOnly == true { Text(task.externalReadOnlyReason ?? "此来源只可查看").font(.system(size: 9)).foregroundStyle(Theme.secondary) }
                    }.frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(task.externalReadOnly == true ? "查看" : "编辑")待办 \(task.title)")
                VStack(alignment: .trailing, spacing: 8) {
                    Button { store.editorEvent = task } label: {
                        Text(task.externalReadOnly == true ? "查看" : "编辑").font(.system(size: 11)).padding(.horizontal, 7).frame(minHeight: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(Theme.jade)
                    if !task.isCompleted {
                        Button { store.scheduleTask(task) } label: {
                            Text("安排时间").font(.system(size: 10)).padding(.horizontal, 7).frame(minHeight: 28).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }
}
