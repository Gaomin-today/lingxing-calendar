import SwiftUI
import LingxiCore

struct LuckCyclesView: View {
    @ObservedObject var store: AppStore
    let profile: BirthProfile
    var editProfile: () -> Void
    @State private var selectedCycle: Int?
    @State private var selectedYear: Int?
    private let engine = LuckCycleEngine()
    var body: some View {
        Group {
            if let gender = profile.luckGender, profile.birthTimeKnown {
                switch Result(catching: { try engine.calculate(for: profile, gender: gender) }) {
                case .failure(let error): Card { Text(error.localizedDescription).foregroundStyle(Theme.vermilion) }
                case .success(let report): content(report)
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("补齐资料，展开你的大运时间轴").font(.system(size: 21, design: .serif))
                        Text("起运需要准确出生时刻和排运所用性别。时间不详时，先保留三柱资料，不给出唯一交运时刻。")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        Button("补充出生档案", action: editProfile).buttonStyle(JadeButton())
                    }
                }
            }
        }.onChange(of: profile) { _, _ in selectedCycle = nil; selectedYear = nil }
    }
    @ViewBuilder private func content(_ report: LuckCycleChart) -> some View {
        let active = report.activeCycle(at: store.selectedDate)
        let cycle = report.cycles.first { $0.index == selectedCycle } ?? active ?? report.cycles.first!
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(profile.name)的大运").font(.system(size: 23, weight: .medium, design: .serif))
                    Spacer(); Pill(text: report.direction.label + " · " + report.gender.label)
                    ExplanationButton(title: "起运怎么算", explanation: report.methodNote + "\n\n" + LuckCycleEngine.boundaryNote, sourceTitle: LuckCycleEngine.sourceTitle, sourceURL: LuckCycleEngine.sourceURL).font(.system(size: 11))
                }
                Text("出生后 \(report.startOffset.years) 年 \(report.startOffset.months) 个月 \(report.startOffset.days) 天 \(report.startOffset.hours) 小时起运")
                    .font(.system(size: 17, design: .serif)).foregroundStyle(Theme.jade)
                Text("首交运：\(localDate(report.startAt)) · \(profile.timeZoneIdentifier)").font(.system(size: 12))
                Text("参考岁数按交运公历年减出生公历年再加一；实际交运以日期和时刻为准。").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Text("\(DateText.format(store.selectedDate, "yyyy年M月d日 HH:mm") + " 北京时间参考")：" + (active.map { "处于第\($0.index)步\($0.pillar.text)大运" } ?? (store.selectedDate < report.birthInstant ? "早于出生日期" : (store.selectedDate < report.startAt ? "尚未交第一步大运" : "已超出展示的十步大运"))))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(report.cycles) { item in
                            Button { selectedCycle = item.index; selectedYear = nil } label: {
                                VStack(spacing: 9) {
                                    Text("第\(item.index)步" + (item.index == active?.index ? " · 当运" : "")).font(.system(size: 10))
                                    Text(item.pillar.text).font(.system(size: 25, weight: .medium, design: .serif))
                                    Text("\(item.nominalStartAge) 岁（参考）").font(.system(size: 10))
                                    Text(localDate(item.start, format: "yyyy.MM")).font(.system(size: 10, design: .monospaced))
                                }.frame(width: 91).padding(.vertical, 14)
                                    .foregroundStyle(item.index == cycle.index ? .white : Theme.ink)
                                    .background(item.index == cycle.index ? Theme.jade : Theme.paper, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).help("交运 \(localDate(item.start))\n下一交运 \(localDate(item.end))")
                        }
                    }.padding(.bottom, 6)
                }
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("\(cycle.pillar.text)大运 · 流年").font(.system(size: 20, weight: .medium, design: .serif)); Spacer()
                    let god = try? BaziRelationshipEngine().tenGod(dayMasterStemIndex: report.birthChart.day.stemIndex, otherStemIndex: cycle.pillar.stemIndex)
                    if let god { ExplanationButton(title: "运干 · " + god.label, explanation: god.explanation.replacingOccurrences(of: "流日", with: "大运"), sourceTitle: god.sourceTitle, sourceURL: god.sourceURL).font(.system(size: 12)) }
                }
                Text("交运 \(localDate(cycle.start)) → 下次交运 \(localDate(cycle.end))").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Text("点击流年查看节月；流年从立春开始。交运首尾可能横跨两个流年，因此一运可列出 11 个流年。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                switch Result(catching: { try engine.flowYears(in: cycle) }) {
                case .failure(let error): Text(error.localizedDescription).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                case .success(let years):
                    let year = years.first { $0.year == selectedYear } ?? years.first { $0.contains(store.selectedDate) } ?? years.first!
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(years) { item in
                            Button { selectedYear = item.year } label: {
                                VStack(spacing: 6) {
                                    Text(String(item.year)).font(.system(size: 12, design: .rounded))
                                    Text(item.pillar.text).font(.system(size: 20, design: .serif))
                                    Text(tenGod(item.pillar, natal: report.birthChart)).font(.system(size: 10))
                                }.frame(maxWidth: .infinity).padding(12)
                                    .background(item.year == year.year ? Theme.softJade : Theme.paper, in: RoundedRectangle(cornerRadius: 9))
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(item.year == year.year ? Theme.jade : .clear, lineWidth: 1))
                            }.buttonStyle(.plain).accessibilityLabel("查看\(item.year)年\(item.pillar.text)流年")
                        }
                    }
                    flowMonths(year, natal: report.birthChart)
                }
            }
        }
    }
    private func flowMonths(_ year: LuckFlowYear, natal: FourPillarsChart) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Divider().overlay(Theme.line)
            HStack {
                Text("\(year.year) · \(year.pillar.text)流年十二节月").font(.system(size: 16, design: .serif)); Spacer()
                Button("在日历中查看立春") { jump(year.start) }.buttonStyle(QuietButton()).font(.system(size: 11))
            }
            Text("立春约\(DateText.format(year.start, "yyyy/M/d HH:mm")) → 次年立春约\(DateText.format(year.end, "yyyy/M/d HH:mm")) · 北京时间")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            if let months = try? engine.flowMonths(in: year) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(months) { month in
                        Button { jump(month.start) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(month.label).font(.system(size: 11)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 9)) }
                                Text(month.pillar.text + " · " + tenGod(month.pillar, natal: natal)).font(.system(size: 15, design: .serif))
                                Text(DateText.format(month.start, "M/d") + " 交节起").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.paper, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).disabled(!store.calendar.hasSolarTermData(for: month.start)).help("北京时间约\(DateText.format(month.start, "yyyy/M/d HH:mm"))至\(DateText.format(month.end, "yyyy/M/d HH:mm"))")
                    }
                }
            }
        }
    }
    private func tenGod(_ pillar: Ganzhi, natal: FourPillarsChart) -> String { (try? BaziRelationshipEngine().tenGod(dayMasterStemIndex: natal.day.stemIndex, otherStemIndex: pillar.stemIndex).label) ?? "" }
    private func localDate(_ date: Date, format: String = "yyyy年M月d日 HH:mm") -> String {
        let formatter = DateFormatter(); formatter.dateFormat = format; formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = TimeZone(identifier: profile.timeZoneIdentifier)
        return formatter.string(from: date)
    }
    private func jump(_ instant: Date) { store.select(instant); store.section = "月历" }
}
