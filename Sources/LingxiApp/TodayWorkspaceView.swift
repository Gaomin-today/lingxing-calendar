import SwiftUI
import LingxiCore

struct TodayWorkspaceView: View {
    @ObservedObject var store: AppStore
    @State private var editingProfile: BirthProfile?
    @StateObject private var dashboard = DashboardLayoutStore()
    @State private var layoutDraft: DashboardLayout?
    @State private var dragging: DashboardComponent?
    @State private var cardFrames: [DashboardComponent: CGRect] = [:]
    @State private var editingMilestone: Milestone?
    @State private var layoutFeedback: String?
    private var isArranging: Bool { layoutDraft != nil }
    private var layout: DashboardLayout { layoutDraft ?? dashboard.layout }
    private var displayedComponents: [DashboardComponent] {
        if isArranging { return layout.order }
        return layout.visible.filter { person != nil || ![.hexagram, .personalDay].contains($0) }
    }
    private var person: BirthProfile? { store.birthProfiles.activeProfile }
    private var reading: PersonalDailyReadingReport? {
        guard let profile = person, let natal = store.activeNatalChart,
              let flow = try? FourPillarsEngine().chart(at: store.selectedNoon, timeZone: store.calendar.gregorian.timeZone, dayBoundary: profile.dayBoundary) else { return nil }
        return try? PersonalDailyReadingEngine().analyze(natal: natal, flow: flow, strength: store.strength(for: profile))
    }
    var body: some View {
        VStack(spacing: 0) {
            heading.padding(.horizontal, 28).padding(.top, 23).padding(.bottom, 18)
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isArranging { arrangementBar }
                    if person == nil && !isArranging { welcome }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18, alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 18) {
                        ForEach(displayedComponents) { component in
                            dashboardCard(component)
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: DashboardFramesKey.self, value: [component: geometry.frame(in: .named("dashboard-layout"))])
                                })
                        }
                    }.coordinateSpace(name: "dashboard-layout").onPreferenceChange(DashboardFramesKey.self) { cardFrames = $0 }
                    HStack {
                        Label("历法由本机计算 · 传统解释供自我探索", systemImage: "leaf").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Button("灵宠与五行配色") { store.showingAppearance = true }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.jade)
                    }.padding(.vertical, 4)
                }.padding(28)
            }
        }.sheet(item: $editingProfile) { BirthProfileEditor(profiles: store.birthProfiles, draft: $0) }
            .sheet(item: $editingMilestone) { MilestoneEditor(store: store.milestones, draft: $0) }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.calendar.gregorian.isDateInToday(store.selectedDate) ? "我的今天" : "我的这一天").font(.system(size: 28, weight: .medium, design: .serif))
                    Text("看清时序，把心力放在眼前的安排上").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { step(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(QuietButton()).accessibilityLabel("个人首页前一天")
                DateJumpButton(store: store, title: DateText.format(store.selectedDate, "yyyy年M月d日"))
                Button { step(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(QuietButton()).accessibilityLabel("个人首页后一天")
                Button("今天") { store.select(Date()) }.buttonStyle(QuietButton())
            }
            HStack {
                let info = store.calendar.info(for: store.selectedDate)
                Text("农历" + info.lunarDate + " · " + DateText.format(store.selectedDate, "EEEE")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                if let term = info.solarTerm { Pill(text: term, color: Theme.accent) }
                ForEach(store.calendar.festivals(on: store.selectedDate).prefix(2)) { festival in Pill(text: festival.name, color: Theme.accent) }
                Spacer()
                if !store.birthProfiles.profiles.isEmpty {
                    Picker("个人首页档案", selection: Binding(get: { store.birthProfiles.activeID }, set: { store.birthProfiles.activeID = $0 })) {
                        Text("选择档案").tag(nil as UUID?)
                        ForEach(store.birthProfiles.profiles) { Text($0.name).tag(Optional($0.id)) }
                    }.labelsHidden().frame(maxWidth: 180)
                }
                Button { store.prepareAgentTask(.daily) } label: { Label("交给我的 Agent", systemImage: "sparkles") }.buttonStyle(QuietButton()).font(.system(size: 11))
                Button { layoutDraft = dashboard.layout; layoutFeedback = nil } label: { Label("自定义首页", systemImage: "slider.horizontal.3") }.buttonStyle(QuietButton()).font(.system(size: 11)).disabled(isArranging)
                Menu {
                    Button("新建日程", systemImage: "calendar.badge.plus") { store.newEvent() }
                    Button("新建倒计时", systemImage: "hourglass.badge.plus") { createMilestone(.countdown) }
                    Button("新建纪念日", systemImage: "heart") { createMilestone(.anniversary) }
                } label: { Label("新建", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 12).padding(.vertical, 8).background(Theme.softJade, in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }
    private var arrangementBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("把首页排成你喜欢的样子", systemImage: "hand.draw").font(.system(size: 14, weight: .medium))
                Spacer()
                Button("日程优先") { layoutDraft = .agendaFirst }.buttonStyle(QuietButton())
                Button("恢复默认") { layoutDraft = DashboardLayout() }.buttonStyle(QuietButton())
                Button("取消") { layoutDraft = nil; dragging = nil }.buttonStyle(QuietButton())
                Button("保存布局") { if let layoutDraft { dashboard.save(layoutDraft) }; layoutDraft = nil; dragging = nil }.buttonStyle(JadeButton())
            }.font(.system(size: 11))
            Text(layoutFeedback ?? "拖动卡片顶部的手柄来排序，也可用左右箭头移动。隐藏只收起卡片，不删除任何内容。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }.padding(16).background(Theme.softJade, in: RoundedRectangle(cornerRadius: 12))
    }
    private func dashboardCard(_ component: DashboardComponent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isArranging {
                HStack(spacing: 5) {
                    Label(component.title, systemImage: "line.3.horizontal")
                        .font(.system(size: 11, weight: .medium)).padding(.vertical, 9).padding(.horizontal, 8).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("dashboard-layout"))
                            .onChanged { value in
                                dragging = component
                                if let target = layout.order.first(where: { $0 != component && cardFrames[$0]?.contains(value.location) == true }) {
                                    withAnimation(.easeInOut(duration: 0.16)) { layoutDraft?.move(component, before: target) }
                                }
                            }.onEnded { _ in dragging = nil })
                        .help("拖动以调整位置").accessibilityLabel("拖动排列" + component.title)
                    Spacer(minLength: 0)
                    Button { layoutDraft?.move(component, by: -1) } label: { Image(systemName: "arrow.left").frame(width: 28, height: 28).contentShape(Rectangle()) }
                        .disabled(layout.order.first == component).accessibilityLabel("前移" + component.title)
                    Button { layoutDraft?.move(component, by: 1) } label: { Image(systemName: "arrow.right").frame(width: 28, height: 28).contentShape(Rectangle()) }
                        .disabled(layout.order.last == component).accessibilityLabel("后移" + component.title)
                    Button {
                        let changed = layoutDraft?.setVisible(layout.hidden.contains(component), for: component) ?? false
                        layoutFeedback = changed ? nil : "至少保留一个首页组件。"
                    } label: { Image(systemName: layout.hidden.contains(component) ? "eye.slash" : "eye").frame(width: 28, height: 28).contentShape(Rectangle()) }
                        .accessibilityLabel((layout.hidden.contains(component) ? "显示" : "隐藏") + component.title)
                }.buttonStyle(.plain).foregroundStyle(Theme.jade)
            }
            componentContent(component).allowsHitTesting(!isArranging).opacity(isArranging && layout.hidden.contains(component) ? 0.3 : 1)
        }
        .padding(isArranging ? 8 : 0)
        .background { if isArranging { RoundedRectangle(cornerRadius: 16).fill(Theme.softJade.opacity(dragging == component ? 0.75 : 0.3)) } }
        .contentShape(Rectangle())
    }
    @ViewBuilder private func componentContent(_ component: DashboardComponent) -> some View {
        switch component {
        case .hexagram:
            if let profile = person { PersonalHexagramSummary(store: store, profile: profile) }
            else { profilePlaceholder("我的今日卦") }
        case .personalDay:
            if let profile = person { personalDay(profile) }
            else { profilePlaceholder("这一天，与你") }
        case .agenda: agenda
        case .preparation: preparation
        case .milestones: MilestoneHomeCard(store: store.milestones, profiles: store.birthProfiles, selectedDate: store.selectedDate, onSelectDate: { store.select($0); store.section = "日历" })
        case .notes: notes
        }
    }
    private func profilePlaceholder(_ title: String) -> some View {
        Card { VStack(alignment: .leading, spacing: 10) { Text(title).font(.system(size: 19, design: .serif)); Text("建立档案后显示个人内容").font(.system(size: 12)).foregroundStyle(Theme.secondary) }.frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading) }
    }
    private func createMilestone(_ kind: MilestoneKind) {
        do { editingMilestone = try Milestone.draft(kind: kind, on: store.selectedDate) }
        catch { store.status = error.localizedDescription }
    }
    private var welcome: some View {
        Card {
            HStack(spacing: 26) {
                SpiritView(size: 96)
                VStack(alignment: .leading, spacing: 12) {
                    Text("从一份出生档案开始").font(.system(size: 24, design: .serif))
                    Text("填写后，这里会呈现你的今日卦、日主关系与旺衰初判。时刻不详也可以先建档，缺失信息会清楚标出。")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary).lineSpacing(4)
                    Button("建立我的档案") { editingProfile = BirthProfile() }.buttonStyle(JadeButton())
                }
                Spacer()
            }.padding(.vertical, 18)
        }
    }
    private func personalDay(_ profile: BirthProfile) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Text("这一天，与你").font(.system(size: 19, weight: .medium, design: .serif)); Spacer(); Pill(text: "正午参考") }
                if let report = reading, let day = report.periods.last {
                    Text(day.tenGod.label).font(.system(size: 34, weight: .medium, design: .serif)).foregroundStyle(Theme.jade)
                    Text(day.theme).font(.system(size: 13, weight: .medium))
                    Text("日主 \(report.dayMaster) · 流月 \(report.flowMonth.pillar.text)").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Text(day.action).font(.system(size: 12)).lineSpacing(4)
                } else {
                    Text("命盘仍有待核对的信息").font(.system(size: 18, design: .serif))
                    Text("多候选盘会保留差异，补充出生资料后再看唯一的个人关系。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Divider().overlay(Theme.line)
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.strength(for: profile).label).font(.system(size: 12, weight: .medium))
                        Text(store.strengthSource(for: profile)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("看依据") { store.section = "四柱与八字"; store.baziPage = .natal }.buttonStyle(QuietButton()).font(.system(size: 11))
                }
                Button("展开每日解读") { store.section = "四柱与八字"; store.baziPage = .daily }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.jade)
            }.frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
        }
    }
    private var agenda: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack { Text("日程与待办").font(.system(size: 19, weight: .medium, design: .serif)); Spacer(); Text("\(store.occurrences.count) 项").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                if store.occurrences.isEmpty {
                    Text("给这一天留一点余地").font(.system(size: 15, design: .serif)).padding(.top, 10)
                    Text("还没有安排。可以添加一件想完成的小事。").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                ForEach(store.occurrences.prefix(4)) { occurrence in EventRow(store: store, occurrence: occurrence) }
                HStack {
                    Button("添加安排") { store.newEvent() }.buttonStyle(QuietButton())
                    Spacer()
                    Button("查看时间轴") { store.calendarMode = .day; store.section = "日历" }.buttonStyle(.plain).foregroundStyle(Theme.jade)
                }.font(.system(size: 11)).padding(.top, 6)
                if store.pendingTasks.contains(where: { !$0.hasDueDate }) {
                    Button("还有未设期限的待办，去看看") { store.section = "待办" }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }
    private var preparation: some View {
        let event = store.occurrences.first(where: { !$0.event.isCompleted })?.event
        let advice = AdviceEngine().advice(for: event?.title ?? "日常安排", on: store.selectedDate)
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("把建议落到行动").font(.system(size: 19, weight: .medium, design: .serif)); Spacer(); Image(systemName: "leaf").foregroundStyle(Theme.accent) }
                if let event { Text("围绕「\(event.title)」").font(.system(size: 12, weight: .medium)).lineLimit(2) }
                Text(advice.action).font(.system(size: 13)).lineSpacing(6)
                Text("现实准备建议 · 不随卦象自动改动日程").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Divider().overlay(Theme.line)
                Button { store.prepareAgentTask(event == nil ? .daily : .event, event: event, on: store.selectedDate) } label: {
                    Label("让我的 Agent 结合详情分析", systemImage: "sparkles")
                }.buttonStyle(QuietButton()).font(.system(size: 11))
                Button("分析回写后，可到日笺查看") { store.section = "日笺" }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.jade).padding(.vertical, 4)
            }
        }
    }
    private var notes: some View {
        let entries = store.dayNotes.entries(on: DateText.format(store.selectedDate, "yyyy-MM-dd"), profileID: store.birthProfiles.activeID)
        return Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack { Text("留给这一天的日笺").font(.system(size: 19, weight: .medium, design: .serif)); Spacer(); Button("打开日笺") { store.section = "日笺" }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.jade) }
                if entries.isEmpty { Text("写下自己的感受，或让 Agent 把分析带回来。").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                ForEach(entries.prefix(3)) { note in
                    Button { store.open(note: note) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(note.title).font(.system(size: 13, weight: .medium)); Spacer(); Text(note.source == .agent ? (note.author ?? "Agent") : "自己记录").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                            Text(note.body).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(2)
                            if store.dayNotes.isStale(note, profiles: store.birthProfiles.profiles) { Text("资料已变更 · 待重新分析").font(.system(size: 10)).foregroundStyle(Theme.vermilion) }
                        }.padding(12).background(Theme.softAccent.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func step(_ amount: Int) { if let date = store.calendar.gregorian.date(byAdding: .day, value: amount, to: store.selectedDate) { store.select(date) } }
}

private struct DashboardFramesKey: PreferenceKey {
    static let defaultValue: [DashboardComponent: CGRect] = [:]
    static func reduce(value: inout [DashboardComponent: CGRect], nextValue: () -> [DashboardComponent: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
