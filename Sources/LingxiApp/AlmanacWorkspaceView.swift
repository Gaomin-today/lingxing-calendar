import SwiftUI
import LingxiCore

struct AlmanacWorkspaceView: View {
    @ObservedObject var store: AppStore
    @State private var selectedHour = 6
    var body: some View {
        switch Result(catching: { try AlmanacEngine.shared.day(on: store.selectedDate) }) {
        case .failure(let error): Card { Text(error.localizedDescription).foregroundStyle(Theme.vermilion) }
        case .success(let day):
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(DateText.format(store.selectedDate, "M月d日") + " · " + day.dayGanZhi + "日").font(.system(size: 24, weight: .medium, design: .serif))
                                Text("传统黄历 · 北京时间").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            ExplanationButton(title: "黄历口径", explanation: day.boundaryNote, sourceTitle: day.sourceLabel, sourceURL: day.sourceURL).font(.system(size: 11))
                        }
                        HStack(alignment: .top, spacing: 16) {
                            activities("传统宜", items: day.yi, color: Theme.jade)
                            activities("传统忌", items: day.ji, color: Theme.vermilion)
                        }
                        Text("宜忌是通用传统条目，个人解读另见“每日解读”。安排事情仍应以现实条件为依据。")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        Divider().overlay(Theme.line)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 15) {
                            fact("值神", value: "\(day.dutyGod) · \(day.dutyGodType) · \(day.luck)", note: "黄道、黑道及吉凶是该版本规则中的传统分类，不是事件成功率。")
                            fact("建除十二神", value: day.officer, note: "按日支与月建相对位置得到的十二值日名称；此处按交节日期切换月建，与八字按交节瞬间切换有不同口径。")
                            fact("冲 / 煞", value: day.clash + " · 煞" + day.sha, note: "冲表示传统地支对应关系，煞为传统方向标签；不表示这个方向现实中必然不利。")
                            fact("物候", value: day.wuHou + " · " + day.hou, note: "七十二候是传统季节物候序列，实际动植物现象随地域和天气变化。")
                            fact("月相名称", value: day.moonPhase, note: "按农历日期给出的传统月相名称，不是实时月面亮度观测。")
                            fact("星宿", value: day.mansion + " · " + day.mansionLuck, note: "二十八宿的值日分类及传统评价，保留规则原名称。")
                        }
                    }
                }
                solarTerms
                ForEach(store.calendar.festivals(on: store.selectedDate)) { FestivalCard(festival: $0) }
                Card {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("一日时辰").font(.system(size: 21, weight: .medium, design: .serif)); Spacer()
                            Text("点选查看 · 子时分为早子与晚子").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 7)], spacing: 7) {
                            ForEach(day.hours) { hour in
                                Button { selectedHour = hour.id } label: {
                                    VStack(spacing: 7) {
                                        HStack { Text(hour.label); Spacer(); Text(hour.luck).font(.system(size: 10)) }.font(.system(size: 12))
                                        Text(hour.ganZhi).font(.system(size: 21, design: .serif))
                                        Text(hour.timeRange).font(.system(size: 9, design: .monospaced))
                                    }.padding(11).frame(maxWidth: .infinity)
                                        .foregroundStyle(selectedHour == hour.id ? .white : Theme.ink)
                                        .background(selectedHour == hour.id ? Theme.jade : Theme.paper, in: RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain).accessibilityLabel("查看\(hour.label)\(hour.timeRange)")
                            }
                        }
                        if let hour = day.hours.first(where: { $0.id == selectedHour }) { hourDetail(hour) }
                    }
                }
                Card {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 15) {
                            fact("吉神", value: day.auspiciousGods.joined(separator: " · "), note: "传统黄历的神煞名目，展示该规则表原始分类，不独立推断实际事件。")
                            fact("凶煞", value: day.inauspiciousGods.joined(separator: " · "), note: "传统黄历的神煞名目，不代表现实危险或个人命运。")
                            fact("彭祖百忌", value: day.pengZu.joined(separator: "；"), note: "与天干地支对应的传统口诀，作为民俗原文记录。")
                            fact("方位", value: day.positions.map { $0.label + "：" + $0.direction }.joined(separator: " · "), note: "传统喜神、福神、财神等方位分类，属于文化资料。")
                            fact("其他条目", value: "六曜 \(day.liuYao) · 日禄 \(day.dayLu)\n胎神 \(day.fetalPosition)", note: "保留黄历规则中的六曜、日禄和胎神条目。胎神是民俗方位名称，不提供孕产或健康建议。")
                            fact("九星", value: "年：\(day.yearNineStar.display)\n月：\(day.monthNineStar.display)\n日：\(day.dayNineStar.display)", note: "九星为传统排布系统，年、月按交节日期口径。此处仅列值日分类，不把它作为个人吉凶评分。")
                        }.padding(.top, 16)
                    } label: { Text("更多黄历条目与来源说明").font(.system(size: 13, weight: .medium)) }
                }
            }
        }
    }
    private var solarTerms: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack { Text("二十四节气").font(.system(size: 17, weight: .medium, design: .serif)); Spacer(); Text("\(store.calendar.gregorian.component(.year, from: store.selectedDate))年 · 点击日期跳转").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                if let terms = try? store.calendar.solarTerms(in: store.calendar.gregorian.component(.year, from: store.selectedDate)) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 7)], spacing: 7) {
                        ForEach(terms) { term in
                            Button { store.select(term.date) } label: {
                                HStack {
                                    Text(term.name).font(.system(size: 12))
                                    Spacer()
                                    Text(DateText.format(term.date, "M/d")).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                }.padding(9).background(store.calendar.gregorian.isDate(term.date, inSameDayAs: store.selectedDate) ? Theme.softJade : Theme.paper, in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain).help("\(term.name) · 北京时间约\(DateText.format(term.date, "yyyy/M/d HH:mm"))" + (term.isJie ? " · 换月的节" : " · 中气"))
                        }
                    }
                }
            }
        }
    }
    private func hourDetail(_ hour: AlmanacHour) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Divider()
            HStack {
                Text(hour.label + " · " + hour.ganZhi + " · " + hour.timeRange).font(.system(size: 17, design: .serif)); Spacer()
                Button("在这个时辰安排") {
                    if let instant = store.calendar.gregorian.date(bySettingHour: hour.startMinute / 60, minute: 0, second: 0, of: store.selectedDate) {
                        store.newEvent(at: instant)
                    }
                }.buttonStyle(QuietButton()).font(.system(size: 11))
            }
            Text("\(hour.dutyGod) · \(hour.dutyGodType) · \(hour.luck) · \(hour.clash) · 煞\(hour.sha)").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            HStack(alignment: .top, spacing: 15) { activities("时辰宜", items: hour.yi, color: Theme.jade); activities("时辰忌", items: hour.ji, color: Theme.vermilion) }
            Text(hour.positions.map { $0.label + " " + $0.direction }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }
    }
    private func activities(_ title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            Text(items.isEmpty ? "未列条目" : items.joined(separator: " · ")).font(.system(size: 13)).lineSpacing(5)
        }.padding(14).frame(maxWidth: .infinity, alignment: .topLeading).background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
    private func fact(_ title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ExplanationButton(title: title, explanation: note, sourceTitle: AlmanacEngine.sourceLabel, sourceURL: AlmanacEngine.sourceURL).font(.system(size: 10))
            Text(value.isEmpty ? "未列条目" : value).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }
    }
}
