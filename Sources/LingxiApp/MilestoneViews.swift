import SwiftUI
import LingxiCore

struct MilestoneHomeCard: View {
    @ObservedObject var store: MilestoneStore
    @ObservedObject var profiles: BirthProfileStore
    let selectedDate: Date
    var onSelectDate: ((Date) -> Void)? = nil
    @State private var managing = false
    @State private var editing: Milestone?
    @State private var draftError: String?

    private var snapshot: MilestoneDisplaySnapshot { MilestoneDisplaySnapshot(store: store, profiles: profiles, on: selectedDate) }
    private var selectedDateText: String { (try? MilestoneEngine().dateText(selectedDate)) ?? "—" }
    private var isActualToday: Bool {
        guard let today = try? MilestoneEngine().dateText(Date()) else { return false }
        return today == selectedDateText
    }
    var body: some View {
        let result = snapshot
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("倒计时与纪念日").font(.system(size: 19, weight: .medium, design: .serif))
                    Spacer()
                    Menu {
                        ForEach(MilestoneKind.allCases) { kind in Button("新建" + kind.label) { makeDraft(kind) } }
                    } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).frame(width: 25)
                        .disabled(store.isReadOnly).accessibilityLabel("新建倒计时或纪念日")
                    Button("管理") { managing = true }.buttonStyle(QuietButton()).font(.system(size: 11))
                }
                Text("以选中日 \(selectedDateText) 为基准 · 北京时间\(isActualToday ? "" : "（当前不是系统今天）")")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                if !result.todayEntries.isEmpty {
                    sectionTitle("选中日")
                    ForEach(result.todayEntries) { entry in
                        MilestoneOccurrenceRow(entry: entry, onSelectDate: onSelectDate)
                    }
                }
                if !result.nextSevenEntries.isEmpty {
                    sectionTitle("未来 7 天")
                    ForEach(result.nextSevenEntries.prefix(4)) { entry in
                        MilestoneOccurrenceRow(entry: entry, onSelectDate: onSelectDate)
                    }
                    if result.nextSevenEntries.count > 4 {
                        Button("查看未来 7 天全部 \(result.nextSevenEntries.count) 项") { managing = true }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                }
                if result.todayEntries.isEmpty && result.nextSevenEntries.isEmpty {
                    Text("把值得期待的日子留在这里").font(.system(size: 17, design: .serif))
                    Text("新建一个目标日期或纪念日，也可在「管理」中选择要显示的档案生日。生日默认不显示。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                    Button("新建倒计时") { makeDraft(.countdown) }.buttonStyle(QuietButton()).disabled(store.isReadOnly)
                } else {
                    if !result.fartherEntries.isEmpty {
                        DisclosureGroup("更远日期（\(result.fartherEntries.count) 项）") {
                            ForEach(result.fartherEntries.prefix(5)) { entry in
                                MilestoneOccurrenceRow(entry: entry, onSelectDate: onSelectDate)
                            }
                            if result.fartherEntries.count > 5 {
                                Button("查看全部") { managing = true }.buttonStyle(.plain)
                                    .font(.system(size: 11)).foregroundStyle(Theme.accent)
                            }
                        }.font(.system(size: 12, weight: .medium))
                    }
                }
                if let error = store.error ?? draftError { Text(error).font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
                ForEach(result.errors, id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(Theme.vermilion) }
                Text("首页展示与系统通知分开控制；系统通知需在设置中开启。").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $managing) { MilestoneManager(store: store, profiles: profiles, selectedDate: selectedDate, onSelectDate: onSelectDate) }
        .sheet(item: $editing) { MilestoneEditor(store: store, draft: $0) }
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
            .padding(.top, 2)
    }
    private func makeDraft(_ kind: MilestoneKind) {
        do { editing = try Milestone.draft(kind: kind, on: selectedDate); draftError = nil }
        catch { draftError = error.localizedDescription }
    }
}

struct MilestoneEditor: View {
    @ObservedObject var store: MilestoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Milestone
    @State private var date: Date
    @State private var error: String?
    @State private var original: Milestone?
    @State private var reminder: DateReminder?
    init(store: MilestoneStore, draft: Milestone) {
        self.store = store
        _original = State(initialValue: store.milestones.first { $0.id == draft.id })
        _draft = State(initialValue: draft)
        _date = State(initialValue: (try? MilestoneEngine().civilDate(draft.targetDate)) ?? Date())
        _reminder = State(initialValue: draft.reminder)
    }
    private var valid: Bool {
        var value = draft
        guard let date = try? MilestoneEngine().dateText(date) else { return false }
        value.targetDate = date
        return (try? value.validate()) != nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Text(original == nil ? "留住一个重要日子" : "编辑" + draft.kind.label)
                    .font(.system(size: 25, weight: .medium, design: .serif))
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
            }
            Picker("类型", selection: $draft.kind) {
                ForEach(MilestoneKind.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            TextField("例如：旅行出发、相识纪念日", text: $draft.title).textFieldStyle(.roundedBorder).accessibilityLabel("倒计时或纪念日标题")
            DatePicker(draft.kind == .anniversary ? "纪念日期" : "目标日期", selection: $date,
                       in: dateRange, displayedComponents: .date)
                .environment(\.timeZone, CalendarEngine.timeZone)
                .environment(\.calendar, CalendarEngine().gregorian)
                .environment(\.locale, Locale(identifier: "zh_CN"))
            Toggle("每年重复", isOn: $draft.repeatsAnnually).toggleStyle(.checkbox)
            Text(draft.repeatsAnnually ? "每年寻找下一次相同公历月日，包含当天。\(MilestoneEngine.solarLeapDayNote)" : "单次倒计时到期后显示「已过几天」；单次纪念日显示从该日已经过了几天。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
            DateReminderEditor(reminder: $reminder, title: "目标日期提醒")
            VStack(alignment: .leading, spacing: 7) {
                Text("备注（可选）").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                TextEditor(text: $draft.note).font(.system(size: 13)).frame(height: 90).scrollContentBackground(.hidden)
                    .padding(9).background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
            }
            Text("按首页北京时间的公历自然日计算，不受 Mac 所在时区影响。首页展示与系统通知分开控制。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
            if let error = error ?? store.error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.vermilion) }
            HStack {
                Text("本地保存 · 标题最多 80 字").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("保存", action: save).buttonStyle(JadeButton()).keyboardShortcut(.defaultAction).disabled(!valid || store.isReadOnly)
            }
        }.padding(28).frame(width: 570).background(Theme.paper).foregroundStyle(Theme.ink)
    }
    private var dateRange: ClosedRange<Date> {
        let engine = MilestoneEngine()
        return (try! engine.civilDate("1901-01-01"))...(try! engine.civilDate("2099-12-31"))
    }
    private func save() {
        do {
            draft.targetDate = try MilestoneEngine().dateText(date); draft.updatedAt = Date()
            draft.reminder = reminder
            try draft.validate()
            if store.save(draft, replacing: original) { dismiss() }
            else { error = store.error }
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor private struct MilestoneDisplaySnapshot {
    var entries: [MilestoneOccurrence] = []
    var todayEntries: [MilestoneOccurrence] = []
    var nextSevenEntries: [MilestoneOccurrence] = []
    var fartherEntries: [MilestoneOccurrence] = []
    var errors: [String] = []
    init(store: MilestoneStore, profiles: BirthProfileStore, on date: Date) {
        let engine = MilestoneEngine()
        for item in store.milestones {
            do { entries.append(try engine.occurrence(for: item, on: date)) }
            catch { errors.append(item.title + "：" + error.localizedDescription) }
        }
        for profile in profiles.profiles where profile.birthdayTracking != nil {
            do { if let item = try engine.birthday(for: profile, on: date) { entries.append(item) } }
            catch { errors.append(profile.name + "的生日：" + error.localizedDescription) }
        }
        entries = MilestoneEngine.sorted(entries)
        let selectedText = (try? engine.dateText(date)) ?? ""
        todayEntries = entries.filter { $0.targetDate == selectedText }
        let end = Self.dateByAddingDays(7, to: date)
        let endText = (try? engine.dateText(end)) ?? selectedText
        nextSevenEntries = entries.filter { $0.targetDate > selectedText && $0.targetDate <= endText }
        fartherEntries = entries.filter { $0.targetDate > endText || ($0.targetDate < selectedText && $0.status != .past) }
        // Entries that are already past remain discoverable under the farther
        // section instead of silently disappearing from the home card.
        fartherEntries.append(contentsOf: entries.filter { $0.status == .past && !fartherEntries.contains($0) })
        fartherEntries = MilestoneEngine.sorted(fartherEntries)
    }

    private static func dateByAddingDays(_ days: Int, to date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = CalendarEngine.timeZone
        return calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}

private struct MilestoneOccurrenceRow: View {
    let entry: MilestoneOccurrence
    var onSelectDate: ((Date) -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.source == .birthday ? "birthday.cake" : "calendar.badge.clock")
                .font(.system(size: 16)).foregroundStyle(entry.status == .past ? Theme.secondary : Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Text(entry.detail).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(3)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text(entry.headline).font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(entry.status == .past ? Theme.secondary : Theme.jade)
                if let onSelectDate {
                    Button { onSelectDate(entry.date) } label: {
                        Text("看这一天").font(.system(size: 10)).padding(.horizontal, 7).padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }
        }.padding(.vertical, 8).help(entry.ruleNote ?? entry.detail)
    }
}

private struct MilestoneManager: View {
    @ObservedObject var store: MilestoneStore
    @ObservedObject var profiles: BirthProfileStore
    let selectedDate: Date
    var onSelectDate: ((Date) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Milestone?
    @State private var birthdayEditing: BirthProfile?
    @State private var deleting: Milestone?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("管理重要日子").font(.system(size: 24, design: .serif))
                Spacer()
                Menu("新建") {
                    ForEach(MilestoneKind.allCases) { kind in Button(kind.label) { makeDraft(kind) } }
                }.disabled(store.isReadOnly)
                Button("完成") { dismiss() }.buttonStyle(QuietButton())
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    ForEach(store.milestones) { item in
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                if let entry = try? MilestoneEngine().occurrence(for: item, on: selectedDate) {
                                    MilestoneOccurrenceRow(entry: entry, onSelectDate: { date in onSelectDate?(date); dismiss() })
                                } else { Text(item.title + " · " + item.targetDate) }
                                HStack {
                                    Pill(text: item.kind.label)
                                    if item.reminder != nil { Pill(text: "已设提醒") }
                                    Spacer()
                                    Button("编辑") { editing = item }.buttonStyle(QuietButton())
                                    Button("删除", role: .destructive) { deleting = item }.buttonStyle(QuietButton())
                                }.font(.system(size: 11)).disabled(store.isReadOnly)
                            }
                        }
                    }
                    if store.milestones.isEmpty { Text("还没有倒计时或纪念日，可从右上角新建。").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                    Card {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("选择首页要显示的生日").font(.system(size: 17, weight: .medium, design: .serif))
                            Text("每份档案独立选择，默认关闭；选择生日不会切换当前命盘。首页展示与系统通知分开控制。")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
                            if profiles.profiles.isEmpty { Text("先创建一份出生档案，就能在这里选择生日。").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                            ForEach(profiles.profiles) { profile in birthdayChoice(profile) }
                        }
                    }
                    if let message = error ?? store.error ?? profiles.error { Text(message).font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
                }.padding(.trailing, 5)
            }
        }.padding(26).frame(width: 700, height: 680).background(Theme.paper).foregroundStyle(Theme.ink)
            .sheet(item: $editing) { MilestoneEditor(store: store, draft: $0) }
            .sheet(item: $birthdayEditing) { profile in
                BirthdayReminderEditor(profiles: profiles, profile: profile)
            }
            .confirmationDialog("删除这条记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                if let item = deleting { Button("删除「\(item.title)」", role: .destructive) { _ = store.delete(item); deleting = nil } }
            } message: { Text("只删除本地倒计时或纪念日，不影响日历日程与出生档案。") }
    }
    private func birthdayChoice(_ profile: BirthProfile) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Toggle(profile.name, isOn: Binding(get: { profile.birthdayTracking != nil }, set: { setBirthday(profile.id, to: $0 ? .solar : nil) }))
                    .toggleStyle(.checkbox).font(.system(size: 12))
                Spacer()
                if let tracking = profile.birthdayTracking {
                    Picker("生日历法", selection: Binding(get: { tracking }, set: { setBirthday(profile.id, to: $0) })) {
                        ForEach(BirthdayTracking.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().frame(width: 140)
                    Button(profile.birthdayReminder == nil ? "设提醒" : "提醒设置") {
                        birthdayEditing = profile
                    }.buttonStyle(QuietButton()).font(.system(size: 11))
                }
            }
            if let tracking = profile.birthdayTracking {
                Text(tracking.ruleNote).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(3)
            }
        }.disabled(profiles.isReadOnly)
    }
    private func setBirthday(_ id: UUID, to tracking: BirthdayTracking?) {
        guard var current = profiles.profiles.first(where: { $0.id == id }) else { return }
        let active = profiles.activeID
        current.birthdayTracking = tracking
        if tracking == nil { current.birthdayReminder = nil }
        if profiles.save(current) { profiles.activeID = active; error = nil }
        else { error = profiles.error }
    }
    private func makeDraft(_ kind: MilestoneKind) {
        do { editing = try Milestone.draft(kind: kind, on: selectedDate) }
        catch { self.error = error.localizedDescription }
    }
}
