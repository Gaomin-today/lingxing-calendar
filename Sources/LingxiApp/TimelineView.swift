import SwiftUI
import LingxiCore

struct CalendarModeBar: View {
    @ObservedObject var store: AppStore
    @Binding var detailVisible: Bool
    var body: some View {
        HStack(spacing: 14) {
            Picker("日历视图", selection: $store.calendarMode) { ForEach(CalendarDisplayMode.allCases) { mode in Text(mode.rawValue).tag(mode) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 185).accessibilityLabel("年、月、周、日视图切换")
            Text(modeHint)
                .font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
            Spacer()
            if store.systemLoading { ProgressView().controlSize(.mini) }
            Button { store.showingConnections = true } label: {
                Label(store.sourceCount == 0 ? "连接 Apple 日历" : "已选 \(store.sourceCount) 个系统来源", systemImage: "calendar.badge.clock")
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.jade)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { detailVisible.toggle() }
            } label: {
                Label(detailVisible ? "收起详情" : "显示详情", systemImage: detailVisible ? "sidebar.right" : "sidebar.left")
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .accessibilityLabel(detailVisible ? "收起日期详情" : "显示日期详情")
        }.padding(.horizontal, 26).padding(.vertical, 12).background(Theme.card.opacity(0.7))
    }
    private var modeHint: String {
        switch store.calendarMode {
        case .year: return "纵览全年节气、节日与安排"
        case .month: return "看时节与重要的日子"
        case .week, .day: return "双击空白时段安排 · 拖动日程后确认调整"
        }
    }
}

struct TimelineCalendarView: View {
    @ObservedObject var store: AppStore
    private let hourHeight: CGFloat = 56
    private var days: [Date] { store.calendarMode == .week ? store.planner.weekDays(containing: store.selectedDate) : [store.calendar.gregorian.startOfDay(for: store.selectedDate)] }
    private var allDayAreaHeight: CGFloat {
        days.contains { day in store.occurrences(on: day).filter { $0.event.isAllDay && !$0.event.isTask }.count > 2 } ? 72 : 44
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    DateJumpButton(store: store, title: title)
                    Text("北京时间 · 日程占用时间，待办记录截止日").font(.system(size: 10)).foregroundStyle(Theme.secondary).help("Asia/Shanghai · 历史按当地钟表时间")
                }
                Spacer()
                Button { store.movePeriod(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel(periodLabel(previous: true))
                Button("今天") { store.select(Date()) }
                Button { store.movePeriod(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel(periodLabel(previous: false))
            }.font(.system(size: 11)).buttonStyle(QuietButton()).padding(.horizontal, 22).padding(.vertical, 19)
            HStack(spacing: 0) {
                Text("全天").font(.system(size: 9)).foregroundStyle(Theme.secondary).frame(width: 49)
                ForEach(days, id: \.self) { date in dayHeader(date) }
            }.padding(.trailing, 10).padding(.bottom, 8)
            Divider().overlay(Theme.line)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(0..<24) { hour in
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(String(format: "%02d:00", hour)).font(.system(size: 9, design: .monospaced))
                                    if store.calendarMode == .day && hour % 2 == 1 { Text(branch(for: hour)).font(.system(size: 8)).opacity(0.7) }
                                    Spacer(minLength: 0)
                                }.foregroundStyle(Theme.secondary).frame(width: 43, height: hourHeight, alignment: .topTrailing).padding(.trailing, 6).id(hour)
                            }
                        }
                        ForEach(days, id: \.self) { date in
                            TimelineDayColumn(store: store, date: date, hourHeight: hourHeight, isDayView: days.count == 1)
                        }
                    }.padding(.top, 8).padding(.trailing, 10).padding(.bottom, 10)
                }.onAppear { proxy.scrollTo(8, anchor: .top) }
            }
            HStack {
                Circle().fill(Theme.jade).frame(width: 5, height: 5); Text("本地")
                Circle().fill(Color(hex: 0x678AA2)).frame(width: 5, height: 5); Text("Apple 日历")
                Spacer(); Text("\(Set(days.flatMap { store.occurrences(on: $0).filter { !$0.event.isTask }.map(\.id) }).count) 项日程")
            }.font(.system(size: 9)).foregroundStyle(Theme.secondary).padding(13)
        }
    }
    private var title: String {
        if days.count == 1 { return DateText.day(store.selectedDate) }
        return "\(DateText.format(days[0], "M月d日")) — \(DateText.format(days[6], "M月d日"))"
    }
    private func periodLabel(previous: Bool) -> String {
        switch store.calendarMode {
        case .year: return previous ? "上一年" : "下一年"
        case .week: return previous ? "上一周" : "下一周"
        case .day: return previous ? "前一天" : "后一天"
        case .month: return previous ? "上个月" : "下个月"
        }
    }
    private func branch(for hour: Int) -> String { ["丑时", "寅时", "卯时", "辰时", "巳时", "午时", "未时", "申时", "酉时", "戌时", "亥时", "子时"][hour / 2] }
    private func dayHeader(_ date: Date) -> some View {
        let info = store.calendar.info(for: date)
        let allDay = store.occurrences(on: date).filter { $0.event.isAllDay && !$0.event.isTask }
        return VStack(spacing: 7) {
            Button { store.select(date) } label: {
                VStack(spacing: 4) {
                    HStack(spacing: 5) {
                        Text(DateText.format(date, "E")).font(.system(size: 10))
                        Text(DateText.format(date, "d")).font(.system(size: 16, weight: .medium, design: .rounded))
                    }
                    Text(info.solarTerm ?? store.calendar.festivals(on: date).first?.name ?? info.lunarDay).font(.system(size: 9)).lineLimit(1)
                }.foregroundStyle(store.calendar.gregorian.isDate(date, inSameDayAs: store.selectedDate) ? Theme.jade : Theme.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 6).background(store.calendar.gregorian.isDateInToday(date) ? Theme.softJade : .clear, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            VStack(spacing: 3) {
                if allDay.isEmpty { Text("—").foregroundStyle(Theme.line).frame(height: 18) }
                ForEach(allDay.prefix(2)) { item in
                    Button { store.editorEvent = item.event } label: { Text(item.event.title).font(.system(size: 9)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(4).background(Theme.softJade, in: RoundedRectangle(cornerRadius: 4)) }.buttonStyle(.plain)
                }
                if allDay.count > 2 { AllDayOverflowButton(store: store, date: date, occurrences: allDay) }
            }.frame(height: allDayAreaHeight, alignment: .top)
        }.padding(.horizontal, 4).frame(maxWidth: .infinity)
    }
}

private struct AllDayOverflowButton: View {
    @ObservedObject var store: AppStore
    let date: Date
    let occurrences: [EventOccurrence]
    @State private var showing = false
    var body: some View {
        Button { store.select(date); showing = true } label: {
            Text("另 \(occurrences.count - 2) 项").font(.system(size: 9))
                .frame(maxWidth: .infinity).frame(minHeight: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Theme.jade)
            .accessibilityLabel("查看\(DateText.day(date))全部\(occurrences.count)项全天安排")
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(DateText.day(date) + " · 全天安排").font(.system(size: 14, weight: .medium))
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(occurrences) { occurrence in
                                Button {
                                    showing = false
                                    store.editorEvent = occurrence.event
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(occurrence.event.title).font(.system(size: 12)).lineLimit(2)
                                        Text(occurrence.event.sourceLabel).font(.system(size: 9)).foregroundStyle(Theme.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                        .background(Theme.softJade, in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(height: min(CGFloat(occurrences.count) * 56, 280))
                }.padding(18).frame(width: 320).background(Theme.paper).foregroundStyle(Theme.ink)
            }
    }
}

private struct TimelineDayColumn: View {
    @ObservedObject var store: AppStore
    let date: Date
    let hourHeight: CGFloat
    let isDayView: Bool
    private var segments: [TimelineSegment] { store.planner.timelineSegments(on: date, events: store.allEvents) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(store.calendar.gregorian.isDateInToday(date) ? Theme.softJade.opacity(0.16) : Theme.card.opacity(0.4))
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).onEnded { value in store.newEvent(at: dateAt(y: value.location.y)) })
                ForEach(0..<24) { hour in
                    VStack(spacing: 0) {
                        Rectangle().fill(Theme.line).frame(height: 1)
                        Spacer()
                        Rectangle().fill(Theme.line.opacity(0.35)).frame(height: 1)
                        Spacer()
                    }.frame(height: hourHeight).offset(y: CGFloat(hour) * hourHeight).allowsHitTesting(false)
                }
                Rectangle().fill(Theme.line.opacity(0.8)).frame(width: 1).allowsHitTesting(false)
                ForEach(segments) { segment in
                    block(segment, width: geometry.size.width)
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if store.calendar.gregorian.isDate(context.date, inSameDayAs: date) {
                        let minutes = Double(store.calendar.gregorian.component(.hour, from: context.date) * 60 + store.calendar.gregorian.component(.minute, from: context.date))
                        HStack(spacing: 0) { Circle().fill(Theme.vermilion).frame(width: 5, height: 5); Rectangle().fill(Theme.vermilion.opacity(0.75)).frame(height: 1) }.offset(y: CGFloat(minutes) / 60 * hourHeight).allowsHitTesting(false)
                    }
                }
            }.contentShape(Rectangle())
                .dropDestination(for: String.self) { items, location in
                    guard let id = items.first, id.hasPrefix("lingxing:"), let occurrence = visibleOccurrences.first(where: { "lingxing:" + $0.id == id }) else { return false }
                    store.proposeMove(occurrence, to: dateAt(y: location.y)); return true
                }
        }.frame(height: hourHeight * 24).frame(maxWidth: .infinity)
    }
    private var visibleOccurrences: [EventOccurrence] { store.planner.weekDays(containing: store.selectedDate).flatMap { store.occurrences(on: $0) } }
    private func dateAt(y: CGFloat) -> Date {
        let minutes = min(1425, max(0, Int((y / hourHeight * 60 / 15).rounded()) * 15))
        return store.calendar.gregorian.date(byAdding: .minute, value: minutes, to: store.calendar.gregorian.startOfDay(for: date))!
    }
    private func block(_ segment: TimelineSegment, width: CGFloat) -> some View {
        let entry = segment.occurrence.event
        let blockWidth = max(12, (width - 8) / CGFloat(segment.columnCount) - 3)
        let blockHeight = max(20, CGFloat(segment.dayMinutesEnd - segment.dayMinutesStart) / 60 * hourHeight - 2)
        let color = entry.isExternal ? Color(hex: 0x678AA2) : Theme.jade
        return Button { store.editorEvent = entry } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.system(size: isDayView ? 12 : 10, weight: .medium)).lineLimit(blockHeight > 50 ? 2 : 1)
                if blockHeight > 35 { Text("\(DateText.time(segment.occurrence.start))–\(DateText.time(segment.occurrence.end))").font(.system(size: 8, design: .monospaced)).lineLimit(1) }
                if blockHeight > 65 { Text(entry.sourceLabel).font(.system(size: 8)).lineLimit(1).opacity(0.8) }
                if blockHeight > 88, let location = entry.location, !location.isEmpty { Text(location).font(.system(size: 9)).lineLimit(1) }
                Spacer(minLength: 0)
            }.padding(.horizontal, 6).padding(.vertical, 4).frame(width: blockWidth, height: blockHeight, alignment: .topLeading)
                .foregroundStyle(color).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3) }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.20), lineWidth: 1))
                .clipped()
        }.buttonStyle(.plain).draggable("lingxing:" + segment.occurrence.id)
            .offset(x: 5 + CGFloat(segment.column) * (blockWidth + 3), y: CGFloat(segment.dayMinutesStart) / 60 * hourHeight)
            .help("\(entry.title) · \(DateText.full(segment.occurrence.start)) · \(entry.sourceLabel)\n拖动后可在编辑器确认调整")
            .accessibilityLabel("\(entry.title)，\(DateText.time(segment.occurrence.start))至\(DateText.time(segment.occurrence.end))，\(entry.sourceLabel)")
    }
}

struct FreeTimeCard: View {
    @ObservedObject var store: AppStore
    var body: some View {
        let slots = store.planner.freeSlots(on: store.selectedDate, events: store.allEvents)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("可安排的空档", systemImage: "clock").font(.system(size: 12, weight: .medium))
                Text("09:00–21:00 · 至少 30 分钟 · 按已显示来源计算").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                if slots.isEmpty { Text("这个时段暂时没有连续 30 分钟的空档。").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                ForEach(slots.prefix(3)) { slot in
                    Button { store.newEvent(at: slot.start, durationMinutes: min(60, slot.durationMinutes)) } label: {
                        HStack { Text("\(DateText.time(slot.start))–\(DateText.time(slot.end))"); Spacer(); Text("\(slot.durationMinutes) 分钟"); Image(systemName: "plus") }
                            .font(.system(size: 10)).foregroundStyle(Theme.jade).frame(minHeight: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if slots.count > 3 { Text("另有 \(slots.count - 3) 个空档，可在日视图查看。").font(.system(size: 9)).foregroundStyle(Theme.secondary) }
            }
        }
    }
}
