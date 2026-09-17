import SwiftUI
import LingxiCore

struct MainView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 196)
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                Rectangle().fill(Theme.line).frame(height: 1)
                if store.section == "月历" { CalendarModeBar(store: store) }
                HStack(alignment: .top, spacing: 0) {
                    Group {
                        if store.section == "待办" { TaskListView(store: store) }
                        else if store.section == "岁时民俗" { CultureView(store: store) }
                        else if store.calendarMode == .month { calendarContent }
                        else { TimelineCalendarView(store: store) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle().fill(Theme.line).frame(width: 1)
                    DayDetailView(store: store).frame(width: store.calendarMode == .month || store.section != "月历" ? 304 : 272)
                }
            }
        }
        .background(Theme.paper).foregroundStyle(Theme.ink)
        .frame(minWidth: 1130, minHeight: 790)
        .preferredColorScheme(.light)
        .sheet(item: $store.editorEvent) { EventEditor(store: store, event: $0) }
        .sheet(isPresented: $store.showingChat) { ChatView(store: store, isSheet: true) }
        .sheet(isPresented: $store.showingSettings) { SettingsView(store: store) }
        .sheet(isPresented: $store.showingSources) { SourcesView(store: store) }
        .sheet(isPresented: $store.showingConnections) { SystemConnectionsView(store: store, service: store.system) }
        .overlay(alignment: .bottom) {
            if let status = store.status {
                HStack { Image(systemName: "info.circle"); Text(status).lineLimit(3); Button { store.status = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                    .font(.system(size: 12)).padding(12).background(Theme.ink, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white).shadow(radius: 12).padding(20)
            }
        }
        .onChange(of: store.status) { _, newValue in
            if newValue != nil { Task { try? await Task.sleep(for: .seconds(6)); if store.status == newValue { store.status = nil } } }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack { RoundedRectangle(cornerRadius: 12).fill(Theme.jade).frame(width: 40, height: 40); Image(systemName: "sun.max").font(.system(size: 23, weight: .light)).foregroundStyle(Theme.paper) }
                VStack(alignment: .leading, spacing: 4) { Text("灵性日历").font(.system(size: 19, weight: .semibold, design: .serif)); Text("与时节同行").font(.system(size: 10)).tracking(3).foregroundStyle(Theme.secondary) }
            }.padding(.top, 35).padding(.bottom, 39)
            Text("我的时光").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(Theme.secondary).padding(.bottom, 15)
            navItem("月历", icon: "calendar")
            navItem("待办", icon: "checkmark.circle", count: store.pendingTasks.count)
            navItem("岁时民俗", icon: "leaf")
            Button { store.showingConnections = true } label: { Label("日历与清单来源", systemImage: "rectangle.stack").font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(12) }.buttonStyle(.plain)
            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 24)
            Text("陪伴").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(Theme.secondary).padding(.bottom, 15)
            Button { store.showingChat = true } label: { Label("与阿灵聊聊", systemImage: "bubble.left.and.bubble.right").frame(maxWidth: .infinity, alignment: .leading).padding(11) }.buttonStyle(.plain).font(.system(size: 13))
            Button { store.togglePet() } label: { HStack { Image(systemName: "sparkle"); Text("桌面阿灵"); Spacer(); Circle().fill(store.petVisible ? Theme.jade : Theme.line).frame(width: 6, height: 6) }.padding(11) }.buttonStyle(.plain).font(.system(size: 13))
            Spacer()
            VStack(spacing: 10) {
                SpiritView(size: 72)
                Text("把日子过成自己的节奏").font(.system(size: 11, design: .serif)).foregroundStyle(Theme.jade)
                Text("今天也有小小的好事情。 ").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }.frame(maxWidth: .infinity).padding(.bottom, 28)
            Button { store.showingSettings = true } label: { Label("偏好设置", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, alignment: .leading).padding(10) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            HStack { Text("本地优先"); Spacer(); Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.1")") }.font(.system(size: 9)).foregroundStyle(Theme.secondary.opacity(0.7)).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 20)
        }.padding(.horizontal, 18).background(Theme.panel)
    }
    private func navItem(_ title: String, icon: String, count: Int? = nil) -> some View {
        Button { store.section = title } label: {
            HStack(spacing: 11) { Image(systemName: icon).frame(width: 17); Text(title); Spacer(); if let count, count > 0 { Text("\(count)").font(.system(size: 10)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.jade.opacity(0.1), in: Capsule()) } }
                .font(.system(size: 13, weight: store.section == title ? .semibold : .regular)).padding(12).background(store.section == title ? Theme.softJade : .clear, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(store.section == title ? Theme.jade : Theme.secondary)
        }.buttonStyle(.plain).padding(.bottom, 5)
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) { Text("一日有一日的好光景").font(.system(size: 19, weight: .medium, design: .serif)); Text("观时节 · 安日常 · 心有所栖").font(.system(size: 11)).tracking(2).foregroundStyle(Theme.secondary) }
            Spacer()
            HStack(spacing: 6) { Circle().fill(Theme.jade).frame(width: 5, height: 5); Text("今日 \(store.todayCount) 项安排") }.font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.trailing, 16)
            Button { store.newEvent() } label: { Label("新建日程", systemImage: "plus") }.buttonStyle(JadeButton()).keyboardShortcut("n", modifiers: .command)
        }.padding(.horizontal, 28).padding(.vertical, 22)
    }
    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) { Text(DateText.format(store.visibleMonth, "M月")).font(.system(size: 31, weight: .medium, design: .serif)); Text(DateText.format(store.visibleMonth, "yyyy")).font(.system(size: 16, weight: .light)).foregroundStyle(Theme.secondary) }
                    Text("\(store.calendar.info(for: store.visibleMonth).yearGanZhi)年 · 静心感受时序流转").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { store.moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 10) }.buttonStyle(QuietButton()).accessibilityLabel("上个月")
                Button("今天") { store.select(Date()) }.buttonStyle(QuietButton()).font(.system(size: 11))
                Button { store.moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 10) }.buttonStyle(QuietButton()).accessibilityLabel("下个月")
            }
            HStack(spacing: 0) { ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in Text(day).font(.system(size: 11)).foregroundStyle((day == "六" || day == "日") ? Theme.vermilion : Theme.secondary).frame(maxWidth: .infinity) } }.padding(.top, 8)
            if !store.calendar.hasSolarTermData(for: store.visibleMonth) {
                Text("此年份暂未收录节气；已核实范围为 2025–2027 年。").font(.system(size: 10)).foregroundStyle(Theme.vermilion)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(store.calendar.monthDays(containing: store.visibleMonth), id: \.self) { date in DayCell(store: store, date: date) }
            }
            HStack(spacing: 16) { legend("传统节日", color: Theme.vermilion); legend("岁时 / 神诞", color: Theme.jade); legend("我的日程", color: Color(hex: 0xB5A46C)); Spacer(); Text("北京时间 UTC+8").font(.system(size: 9)).foregroundStyle(Theme.secondary) }.padding(.top, 1)
            Spacer(minLength: 0)
            HStack(spacing: 13) {
                Image(systemName: "leaf").font(.system(size: 20, weight: .light)).foregroundStyle(Theme.jade)
                VStack(alignment: .leading, spacing: 5) { Text("顺应时节，也相信自己的步调。").font(.system(size: 13, design: .serif)); Text("民俗提供一种看待生活的方式，行动让日子向前。 ").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                Spacer()
                Button { store.showingSources = true } label: { Image(systemName: "info.circle").foregroundStyle(Theme.secondary) }.buttonStyle(.plain).help("查看历法口径与资料来源")
            }.padding(17).background(Theme.softJade.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }.padding(25)
    }
    private func legend(_ title: String, color: Color) -> some View { HStack(spacing: 4) { Circle().fill(color).frame(width: 4, height: 4); Text(title).font(.system(size: 9)).foregroundStyle(Theme.secondary) } }
}

struct DayCell: View {
    @ObservedObject var store: AppStore
    let date: Date
    private var selected: Bool { store.calendar.gregorian.isDate(date, inSameDayAs: store.selectedDate) }
    private var inMonth: Bool { store.calendar.gregorian.isDate(date, equalTo: store.visibleMonth, toGranularity: .month) }
    var body: some View {
        let info = store.calendar.info(for: date)
        let festival = store.calendar.festivals(on: date).first
        let entries = store.occurrences(on: date)
        Button { store.selectedDate = date } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(DateText.format(date, "d")).font(.system(size: 17, weight: selected ? .semibold : .regular, design: .rounded)); Spacer(minLength: 0); if store.calendar.gregorian.isDateInToday(date) { Text("今").font(.system(size: 8, weight: .medium)).padding(3).background(selected ? .white.opacity(0.2) : Theme.softJade, in: Circle()) } }
                Text(info.solarTerm ?? festival?.name ?? (info.numericLunarDay == 1 ? info.lunarMonth : info.lunarDay)).font(.system(size: 9)).lineLimit(1).foregroundStyle(selected ? .white.opacity(0.85) : (festival != nil ? Theme.vermilion : (info.solarTerm != nil ? Theme.jade : Theme.secondary)))
                Spacer(minLength: 0)
                if let first = entries.first { HStack(spacing: 3) { Circle().fill(selected ? .white.opacity(0.7) : Color(hex: 0xB5A46C)).frame(width: 3, height: 3); Text(first.event.title).font(.system(size: 8)).lineLimit(1); if entries.count > 1 { Text("+\(entries.count - 1)").font(.system(size: 8)) } } }
            }.padding(9).frame(maxWidth: .infinity).frame(height: 66).background(selected ? Theme.jade : (inMonth ? Theme.card : Theme.panel.opacity(0.35)), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.jade : Theme.line.opacity(0.55), lineWidth: 1)).foregroundStyle(selected ? .white : Theme.ink).opacity(inMonth ? 1 : 0.38)
        }.buttonStyle(.plain).accessibilityLabel("\(DateText.day(date))，农历\(info.lunarDate)，\(entries.count)项安排")
    }
}

struct DayDetailView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        let info = store.calendar.info(for: store.selectedDate)
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                HStack { Text("这一日").font(.system(size: 11)).tracking(2).foregroundStyle(Theme.secondary); Spacer(); if store.calendar.gregorian.isDateInToday(store.selectedDate) { Pill(text: "今日") } }
                HStack(alignment: .bottom, spacing: 14) {
                    Text(DateText.format(store.selectedDate, "dd")).font(.system(size: 58, weight: .light, design: .serif))
                    VStack(alignment: .leading, spacing: 6) { Text(DateText.format(store.selectedDate, "M月 · EEEE")).font(.system(size: 12)); Text("农历\(info.lunarDate)").font(.system(size: 13, design: .serif)).foregroundStyle(Theme.jade) }.padding(.bottom, 10)
                }
                Text("\(info.yearGanZhi)年 · \(info.zodiac)年 · \(info.dayGanZhi)日").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                if let term = info.solarTerm { Label(term, systemImage: "sun.horizon").font(.system(size: 13)).foregroundStyle(Theme.jade) }
                Divider().overlay(Theme.line)
                ForEach(store.calendar.festivals(on: store.selectedDate)) { festival in FestivalCard(festival: festival) }
                HStack { Text("当日安排").font(.system(size: 13, weight: .medium)); Spacer(); Text("\(store.occurrences.count) 项").font(.system(size: 10)).foregroundStyle(Theme.secondary); Button { store.newEvent() } label: { Image(systemName: "plus.circle").foregroundStyle(Theme.jade) }.buttonStyle(.plain).accessibilityLabel("为选中日期添加日程") }
                if store.occurrences.isEmpty {
                    VStack(spacing: 10) { Image(systemName: "sun.haze").font(.system(size: 24, weight: .ultraLight)); Text("留白，也是很好的安排。").font(.system(size: 11)); Button("添一件小事") { store.newEvent() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.jade) }.foregroundStyle(Theme.secondary).frame(maxWidth: .infinity).padding(.vertical, 22).background(Theme.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    ForEach(store.occurrences) { occurrence in EventRow(store: store, occurrence: occurrence) }
                }
                FreeTimeCard(store: store)
                AdviceCard(store: store)
                Button { store.askAboutDay() } label: { HStack { Image(systemName: "sparkles"); Text("和阿灵聊聊这一天"); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 11)).padding(13).background(Theme.softJade, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).foregroundStyle(Theme.jade)
            }.padding(23)
        }.background(Theme.card.opacity(0.35))
    }
}

struct EventRow: View {
    @ObservedObject var store: AppStore
    let occurrence: EventOccurrence
    @State private var deleting = false
    private var timeLabel: String {
        if occurrence.event.isTask { return occurrence.event.taskDueHasTime == false ? "当天到期" : "截止 \(DateText.time(occurrence.start))" }
        if occurrence.event.isAllDay { return "全天" }
        if !store.calendar.gregorian.isDate(occurrence.start, inSameDayAs: occurrence.end) {
            return "\(DateText.format(occurrence.start, "M/d HH:mm")) — \(DateText.format(occurrence.end, "M/d HH:mm"))"
        }
        return "\(DateText.time(occurrence.start)) — \(DateText.time(occurrence.end))"
    }
    var body: some View {
        Button { store.editorEvent = occurrence.event } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.jade.opacity(0.65)).frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(occurrence.event.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    Text(timeLabel).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Text(occurrence.event.sourceLabel).font(.system(size: 8)).foregroundStyle(Theme.secondary)
                    if occurrence.event.repeatRule != .none { Text("\(occurrence.event.repeatRule.label) · 整个系列").font(.system(size: 9)).foregroundStyle(Theme.secondary) }
                }
                Spacer(minLength: 0)
                if occurrence.event.reminderMinutes != nil { Image(systemName: "bell").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        }.buttonStyle(.plain)
        .contextMenu { Button("查看准备建议") { store.askAboutEvent(occurrence.event, on: occurrence.start) }; Button(occurrence.event.externalReadOnly == true ? "查看" : "编辑") { store.editorEvent = occurrence.event }; if occurrence.event.isTask && occurrence.event.externalReadOnly != true { Button("标记完成") { store.toggleCompleted(occurrence.event) } }; Button("删除", role: .destructive) { deleting = true }.disabled(occurrence.event.externalReadOnly == true) }
        .confirmationDialog(occurrence.event.isExternal ? "从系统来源删除「\(occurrence.event.title)」？重复日程仅删除本次。" : "删除「\(occurrence.event.title)」？本地重复日程将删除整个系列。", isPresented: $deleting) { Button("删除", role: .destructive) { store.delete(occurrence.event) } }
    }
}

struct AdviceCard: View {
    @ObservedObject var store: AppStore
    var body: some View {
        let advice = AdviceEngine().advice(for: store.occurrences.first?.event.title ?? "日常安排", on: store.selectedDate)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: "sparkle").foregroundStyle(Theme.jade); Text("给这一天的笺言").font(.system(size: 12, weight: .medium)) }
                adviceLine("行动建议", text: advice.action, color: Theme.jade)
                adviceLine("传统说法", text: advice.tradition, color: Theme.vermilion)
                Text("未接入黄历宜忌数据 · 民俗仅供文化参考").font(.system(size: 8)).foregroundStyle(Theme.secondary)
            }
        }
    }
    private func adviceLine(_ title: String, text: String, color: Color) -> some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(color); Text(text).font(.system(size: 10)).lineSpacing(4).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) } }
}

struct FestivalCard: View {
    let festival: Festival
    var body: some View {
        Card { VStack(alignment: .leading, spacing: 9) { HStack { Text(festival.name).font(.system(size: 14, weight: .medium, design: .serif)); Spacer(); Pill(text: festival.kind, color: Theme.vermilion) }; Text(festival.summary).font(.system(size: 11)).lineSpacing(4); Text(festival.region).font(.system(size: 9)).foregroundStyle(Theme.secondary); if let url = URL(string: festival.sourceURL) { Link("来源：\(festival.sourceTitle) ↗", destination: url).font(.system(size: 9)).foregroundStyle(Theme.jade) } } }
    }
}

struct CultureView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("日子里的文化记忆").font(.system(size: 25, weight: .medium, design: .serif))
                Text("本月节日与神诞 · 民俗因地域和传统而异").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                HStack { Button { store.moveMonth(-1) } label: { Image(systemName: "chevron.left") }; Text(DateText.format(store.visibleMonth, "yyyy年M月")); Button { store.moveMonth(1) } label: { Image(systemName: "chevron.right") } }.buttonStyle(QuietButton()).font(.system(size: 12))
                ForEach(store.calendar.monthDays(containing: store.visibleMonth).filter { store.calendar.gregorian.isDate($0, equalTo: store.visibleMonth, toGranularity: .month) }, id: \.self) { date in
                    let festivals = store.calendar.festivals(on: date)
                    let term = store.calendar.solarTerm(on: date)
                    if !festivals.isEmpty || term != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Button { store.select(date); store.section = "月历" } label: { Text(DateText.day(date)).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.jade) }.buttonStyle(.plain)
                            ForEach(festivals) { festival in FestivalCard(festival: festival) }
                            if let term { Card { HStack { Image(systemName: "sun.horizon"); Text(term); Spacer(); Pill(text: "节气 · 历法事实") }.font(.system(size: 13)) } }
                        }
                    }
                }
                Button("查看资料来源与历法口径") { store.showingSources = true }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.jade)
            }.padding(28)
        }
    }
}
