import SwiftUI
import LingxiCore

struct DayNotesWorkspace: View {
    @ObservedObject var store: AppStore
    @State private var editing: DayNote?
    @State private var allDates = false
    @State private var query = ""
    private var entries: [DayNote] {
        store.dayNotes.notes.filter { note in
            (allDates || note.date == DateText.format(store.selectedDate, "yyyy-MM-dd")) &&
            (store.birthProfiles.activeID == nil || note.profileID == nil || note.profileID == store.birthProfiles.activeID || !store.birthProfiles.profiles.contains(where: { $0.id == note.profileID })) &&
            (query.isEmpty || note.title.localizedCaseInsensitiveContains(query) || note.body.localizedCaseInsensitiveContains(query))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("日笺与解读").font(.system(size: 27, weight: .medium, design: .serif))
                    Text("留住自己的记录，也接住 Agent 带回的建议").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                DateJumpButton(store: store, title: DateText.format(store.selectedDate, "yyyy年M月d日"))
                Button("写一篇") { editing = newNote() }.buttonStyle(JadeButton()).disabled(store.dayNotes.isReadOnly)
            }
            HStack {
                TextField("搜索标题或正文", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 330)
                Toggle("查看所有日期", isOn: $allDates).toggleStyle(.checkbox).font(.system(size: 11))
                Spacer()
                Text(store.birthProfiles.activeProfile.map { "档案 · " + $0.name } ?? "全部档案").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            if let error = store.dayNotes.error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.vermilion) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if entries.isEmpty {
                            Card {
                                VStack(alignment: .leading, spacing: 16) {
                                    Image(systemName: "book.pages").font(.system(size: 35, weight: .ultraLight)).foregroundStyle(Theme.jade)
                                    Text("这里还没有日笺").font(.system(size: 21, design: .serif))
                                    Text("可以自己写一段，也可以让你使用的 Agent 读取命盘与日程后，把分析保存到这里。")
                                        .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                                    Button("查看外部 Agent 接入") { store.showingAutomation = true }.buttonStyle(QuietButton())
                                }.padding(.vertical, 20)
                            }
                        }
                        ForEach(entries) { note in
                            DayNoteCard(store: store, note: note) { editing = note }.id(note.id)
                        }
                    }.padding(.bottom, 24)
                }.onAppear { if let id = store.highlightedNoteID { proxy.scrollTo(id, anchor: .top) } }
                    .onChange(of: store.highlightedNoteID) { _, id in
                        query = ""
                        if let id { proxy.scrollTo(id, anchor: .top) }
                    }
            }
        }.padding(28).sheet(item: $editing) { DayNoteEditor(store: store, note: $0) }
    }
    private func newNote() -> DayNote {
        DayNote(kind: .journal, date: DateText.format(store.selectedDate, "yyyy-MM-dd"), profileID: store.birthProfiles.activeID, title: "", body: "", source: .user)
    }
}

struct DayNoteCard: View {
    @ObservedObject var store: AppStore
    let note: DayNote
    var edit: () -> Void
    @State private var deleting = false
    @State private var deletionSnapshot: DayNote?
    @State private var deletionError: String?
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Pill(text: note.kind.label)
                    Text(note.date).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(note.source == .agent ? (note.author ?? "Agent") + " · 写入" : "自己记录").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Button("编辑", action: edit).buttonStyle(.plain).font(.system(size: 11))
                    Button { deletionError = nil; deletionSnapshot = note; deleting = true } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("删除日笺\(note.title)")
                }
                Text(note.title).font(.system(size: 21, weight: .medium, design: .serif)).textSelection(.enabled)
                if store.dayNotes.isStale(note, profiles: store.birthProfiles.profiles) {
                    Label("出生资料已变化或缺少版本依据，这篇分析仅保留作记录；请重新生成。", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11)).foregroundStyle(Theme.vermilion)
                }
                if let strength = note.strengthAssessment { Pill(text: "Agent 分析 · " + strength.label) }
                Text(note.body).font(.system(size: 13)).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                Text("更新于 " + DateText.full(note.updatedAt)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                if let deletionError { Text(deletionError).font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
            }
        }.overlay(RoundedRectangle(cornerRadius: 14).stroke(store.highlightedNoteID == note.id ? Theme.jade : .clear, lineWidth: 1))
            .confirmationDialog("删除这篇日笺？", isPresented: $deleting) {
                Button("删除「\(deletionSnapshot?.title ?? note.title)」", role: .destructive, action: deleteConfirmedSnapshot)
            } message: { Text("只删除这篇内容，不影响命盘和日程。") }
    }
    private func deleteConfirmedSnapshot() {
        guard let snapshot = deletionSnapshot else { return }
        defer { deletionSnapshot = nil }
        guard let current = store.dayNotes.notes.first(where: { $0.id == snapshot.id }),
              (try? AutomationSnapshot.revision(current)) == (try? AutomationSnapshot.revision(snapshot)) else {
            deletionError = "这篇日笺已在别处修改或删除，未执行本次删除。请重新查看最新内容。"
            return
        }
        if store.dayNotes.delete(snapshot) { deletionError = nil }
        else { deletionError = store.dayNotes.error ?? "日笺未删除，请重新查看后再试。" }
    }
}

struct DayNoteEditor: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DayNote
    @State private var date: Date
    @State private var error: String?
    @State private var originalRevision: String?
    init(store: AppStore, note: DayNote) {
        self.store = store; _draft = State(initialValue: note)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = store.calendar.gregorian.timeZone
        _date = State(initialValue: formatter.date(from: note.date) ?? store.selectedDate)
        _originalRevision = State(initialValue: store.dayNotes.notes.contains(where: { $0.id == note.id }) ? try? AutomationSnapshot.revision(note) : nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text("写下这一天").font(.system(size: 24, design: .serif)); Spacer(); Button("取消") { dismiss() }.buttonStyle(QuietButton()) }
            HStack {
                DatePicker("日期", selection: $date, displayedComponents: .date).environment(\.timeZone, store.calendar.gregorian.timeZone)
                Picker("类型", selection: $draft.kind) { ForEach(DayNoteKind.allCases) { Text($0.label).tag($0) } }
            }
            Picker("关联档案", selection: $draft.profileID) {
                Text("不关联档案").tag(nil as UUID?)
                ForEach(store.birthProfiles.profiles) { Text($0.name).tag(Optional($0.id)) }
            }
            TextField("标题", text: $draft.title).textFieldStyle(.roundedBorder)
            TextEditor(text: $draft.body).font(.system(size: 14)).scrollContentBackground(.hidden).padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            Text("在这里编辑后标为个人整理。Agent 的自动旺衰结论不会随手工改写继续沿用。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.vermilion) }
            HStack { Spacer(); Button("保存日笺", action: save).buttonStyle(JadeButton()).disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(26).frame(width: 660, height: 660).background(Theme.paper)
    }
    private func save() {
        let current = store.dayNotes.notes.first { $0.id == draft.id }
        guard (try? current.map(AutomationSnapshot.revision)) == originalRevision else { error = "这篇日笺已在别处修改或删除，请关闭并重新打开后编辑。"; return }
        draft.date = DateText.format(date, "yyyy-MM-dd"); draft.source = .user; draft.author = nil; draft.strengthAssessment = nil; draft.updatedAt = Date()
        if let person = store.birthProfiles.profiles.first(where: { $0.id == draft.profileID }) { draft.profileRevision = try? person.analysisRevision() }
        else { draft.profileRevision = nil }
        if store.dayNotes.save(draft) { dismiss() } else { error = store.dayNotes.error }
    }
}

struct DayNotesSummaryCard: View {
    @ObservedObject var store: AppStore
    var body: some View {
        let notes = store.dayNotes.entries(on: DateText.format(store.selectedDate, "yyyy-MM-dd"), profileID: store.birthProfiles.activeID)
        if !notes.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 11) {
                    HStack { Text("这一天的日笺").font(.system(size: 13, weight: .medium)); Spacer(); Text("\(notes.count)篇").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                    ForEach(notes.prefix(3)) { note in
                        Button { store.highlightedNoteID = note.id; store.section = "日笺" } label: {
                            HStack { Image(systemName: note.kind == .insight ? "sparkles" : "book"); Text(note.title).lineLimit(2); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 11)).foregroundStyle(Theme.jade)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
