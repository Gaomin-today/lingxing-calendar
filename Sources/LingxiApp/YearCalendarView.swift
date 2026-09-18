import SwiftUI
import LingxiCore

/// A compact annual overview. It deliberately reuses the same month-day and
/// festival calculations as the month view; selecting a cell always goes
/// through AppStore.select so the detail panel and system query stay aligned.
struct YearCalendarView: View {
    @ObservedObject var store: AppStore
    private var calendar: Calendar { store.calendar.gregorian }
    private var year: Int { calendar.component(.year, from: store.visibleMonth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                DateJumpButton(store: store, title: "\(year) 年", large: true, focusDate: store.visibleMonth)
                Text("节气 · 节日 · 日程一览").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
                Button { store.movePeriod(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(QuietButton()).accessibilityLabel("上一年")
                Button("今年") { store.visibleMonth = Date(); store.select(Date()) }
                    .buttonStyle(QuietButton()).font(.system(size: 11))
                Button { store.movePeriod(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(QuietButton()).accessibilityLabel("下一年")
            }
            Text("点击任意日期查看右侧详情，双击日程时间轴可直接安排事项。")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 16) {
                ForEach(1...12, id: \.self) { month in
                    YearMonthCard(store: store, year: year, month: month)
                }
            }
        }.padding(24)
    }
}

private struct YearMonthCard: View {
    @ObservedObject var store: AppStore
    let year: Int
    let month: Int
    private var calendar: Calendar { store.calendar.gregorian }
    private var monthDate: Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12))!
    }
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(month) 月").font(.system(size: 13, weight: .semibold, design: .serif))
                Spacer()
                if let term = store.calendar.monthDays(containing: monthDate).compactMap({ store.calendar.info(for: $0).solarTerm }).first {
                    Text(term).font(.system(size: 8)).foregroundStyle(Theme.jade).lineLimit(1)
                }
            }
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day).font(.system(size: 8)).foregroundStyle((day == "六" || day == "日") ? Theme.vermilion : Theme.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(store.calendar.monthDays(containing: monthDate), id: \.self) { date in
                    let info = store.calendar.info(for: date)
                    let inMonth = calendar.component(.year, from: date) == year && calendar.component(.month, from: date) == month
                    let selected = calendar.isDate(date, inSameDayAs: store.selectedDate)
                    let hasEvent = !store.occurrences(on: date).isEmpty
                    let festival = store.calendar.festivals(on: date).first
                    Button { store.select(date) } label: {
                        VStack(spacing: 1) {
                            Text(DateText.format(date, "d")).font(.system(size: 9, weight: selected ? .semibold : .regular, design: .rounded))
                            Circle().fill(festival != nil ? Theme.vermilion : (hasEvent ? Theme.accent : .clear)).frame(width: 3, height: 3)
                        }.frame(maxWidth: .infinity).frame(height: 21)
                            .background(selected ? Theme.jade : (calendar.isDateInToday(date) ? Theme.softJade : .clear), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(selected ? .white : (festival != nil ? Theme.vermilion : (inMonth ? Theme.ink : Theme.secondary.opacity(0.35))))
                    }.buttonStyle(.plain).disabled(!inMonth).accessibilityLabel("\(DateText.day(date))，农历\(info.lunarDate)")
                }
            }
        }.padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line.opacity(0.7), lineWidth: 1))
    }
}
