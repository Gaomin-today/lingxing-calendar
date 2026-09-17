import SwiftUI
import LingxiCore

/// One date selection path keeps the visible calendar and EventKit query in sync.
struct DateJumpButton: View {
    @ObservedObject var store: AppStore
    var title: String
    var large = false
    var focusDate: Date?
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 8) {
                Text(title).font(.system(size: large ? 27 : 15, weight: .medium, design: .serif))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).help("选择年份、月份或直接跳转日期")
            .accessibilityLabel("选择日期，\(title)")
            .popover(isPresented: $showing) {
                DateJumpPicker(store: store, isPresented: $showing, date: focusDate ?? store.selectedDate)
            }
    }
}

private struct DateJumpPicker: View {
    @ObservedObject var store: AppStore
    @Binding var isPresented: Bool
    @State var date: Date
    private var calendar: Calendar { store.calendar.gregorian }
    private var year: Int { calendar.component(.year, from: date) }
    private var month: Int { calendar.component(.month, from: date) }
    private var supported: ClosedRange<Date> {
        calendar.date(from: DateComponents(year: 1901, month: 1, day: 1))! ... calendar.date(from: DateComponents(year: 2099, month: 12, day: 31, hour: 23, minute: 59))!
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("去往某一天").font(.system(size: 18, weight: .medium, design: .serif))
                Spacer()
                Button("今天") { choose(Date()) }.buttonStyle(.plain).foregroundStyle(Theme.jade)
            }
            HStack {
                Picker("年份", selection: Binding(get: { year }, set: { setMonth(year: $0, month: month) })) {
                    ForEach(1901...2099, id: \.self) { Text(String($0) + " 年").tag($0) }
                }.frame(width: 140)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.disabled(year == 1901 && month == 1).accessibilityLabel("跳转面板上个月")
                Text("\(month)月").frame(width: 32)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.disabled(year == 2099 && month == 12).accessibilityLabel("跳转面板下个月")
            }.buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 6), spacing: 6) {
                ForEach(1...12, id: \.self) { value in
                    Button { setMonth(year: year, month: value) } label: {
                        Text("\(value)月").font(.system(size: 11)).frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(value == month ? Theme.softJade : Theme.paper, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }
            }
            Divider()
            HStack { ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.system(size: 10)).frame(maxWidth: .infinity).foregroundStyle(Theme.secondary) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(store.calendar.monthDays(containing: date), id: \.self) { value in
                    Button { choose(value) } label: {
                        Text(DateText.format(value, "d")).font(.system(size: 12, design: .rounded)).frame(maxWidth: .infinity).frame(height: 30)
                            .background(calendar.isDate(value, inSameDayAs: store.selectedDate) ? Theme.softJade : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(calendar.isDate(value, equalTo: date, toGranularity: .month) ? Theme.ink : Theme.secondary.opacity(0.5))
                    }.buttonStyle(.plain).disabled(!supported.contains(value)).accessibilityLabel("跳转到\(DateText.day(value))")
                }
            }
            Divider()
            HStack {
                DatePicker("直接输入", selection: $date, in: supported, displayedComponents: .date)
                    .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone).environment(\.locale, Locale(identifier: "zh_CN"))
                Spacer()
                Button("前往") { choose(date) }.buttonStyle(JadeButton())
            }
        }.padding(22).frame(width: 350).background(Theme.paper)
    }
    private func setMonth(year: Int, month: Int) { date = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12))! }
    private func shift(_ direction: Int) { if let next = calendar.date(byAdding: .month, value: direction, to: date), supported.contains(next) { date = next } }
    private func choose(_ value: Date) { store.select(value); isPresented = false }
}

struct DayNavigationStrip: View {
    @ObservedObject var store: AppStore
    var body: some View {
        HStack(spacing: 3) {
            ForEach(-3...3, id: \.self) { offset in
                let day = store.calendar.gregorian.date(byAdding: .day, value: offset, to: store.selectedDate)!
                Button { store.select(day) } label: {
                    VStack(spacing: 4) {
                        Text(DateText.format(day, "EEEEE")).font(.system(size: 8))
                        Text(DateText.format(day, "d")).font(.system(size: 12, weight: offset == 0 ? .semibold : .regular, design: .rounded))
                    }.frame(maxWidth: .infinity).padding(.vertical, 7)
                        .foregroundStyle(offset == 0 ? .white : Theme.secondary)
                        .background(offset == 0 ? Theme.jade : Theme.paper, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).accessibilityLabel("查看\(DateText.day(day))")
            }
        }
    }
}
