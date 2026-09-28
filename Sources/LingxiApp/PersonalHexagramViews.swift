import SwiftUI
import LingxiCore

struct HexagramDrawing: View {
    let marked: HeluoMarkedHexagram
    var width: CGFloat = 84
    var body: some View {
        VStack(spacing: width * 0.085) {
            ForEach(Array(marked.hexagram.lines.enumerated().reversed()), id: \.offset) { index, yang in
                HStack(spacing: width * 0.17) {
                    if yang { Capsule().fill(index + 1 == marked.linePosition ? Theme.accent : Theme.jade) }
                    else {
                        Capsule().fill(index + 1 == marked.linePosition ? Theme.accent : Theme.jade)
                        Capsule().fill(index + 1 == marked.linePosition ? Theme.accent : Theme.jade)
                    }
                }.frame(width: width, height: width * 0.095)
                    .overlay(alignment: .trailing) {
                        if index + 1 == marked.linePosition { Circle().fill(Theme.accent).frame(width: 4, height: 4).offset(x: 11) }
                    }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(marked.hexagram.name)，下\(marked.hexagram.lower)上\(marked.hexagram.upper)，当前\(marked.lineLabel)")
    }
}

struct PersonalHexagramSummary: View {
    @ObservedObject var store: AppStore
    let profile: BirthProfile
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Text("我的今日卦").font(.system(size: 19, weight: .medium, design: .serif)); Spacer(); Pill(text: "河洛理数", color: Theme.accent) }
                switch store.personalHexagrams(for: profile, at: store.selectedNoon) {
                case .failure(let error):
                    Text("补齐资料，再看属于你的卦").font(.system(size: 20, design: .serif))
                    Text(error.localizedDescription).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                case .success(let report):
                    if let day = report.day {
                        HStack(spacing: 28) {
                            HexagramDrawing(marked: day.marked, width: 78).padding(.trailing, 10)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(day.marked.hexagram.name).font(.system(size: 36, weight: .medium, design: .serif)).foregroundStyle(Theme.jade)
                                Text(day.marked.hexagram.theme).font(.system(size: 12))
                                Text("值日 · " + day.marked.lineLabel).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            }
                        }.padding(.vertical, 5)
                        Text(day.marked.hexagram.reflection).font(.system(size: 12)).lineSpacing(4)
                        HStack {
                            Text("年 · " + (report.year?.marked.hexagram.name ?? "—"))
                            Text("月 · " + (report.month?.marked.hexagram.name ?? "—"))
                        }.font(.system(size: 11)).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("北京时间 12:00 参考 · 换日按 \(report.timeZoneIdentifier)")
                            if report.timeZoneIdentifier != "Asia/Shanghai" {
                                Text("对应当地 " + HeluoDateText.format(report.instant, zone: report.timeZoneIdentifier))
                            }
                            Text("交节日可能分段，详情可切换参考时刻。")
                        }.font(.system(size: 9)).foregroundStyle(Theme.secondary)
                    } else {
                        Text(report.xianTian.hexagram.name + " · 先天卦").font(.system(size: 25, design: .serif))
                        Text(report.flowUnavailableReason ?? "该时段暂无值日卦。").font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                    }
                }
                Spacer(minLength: 0)
                Button("先后天 · 年月日卦详情") { store.baziPage = .hexagrams; store.section = "四柱与八字" }.buttonStyle(QuietButton()).font(.system(size: 11))
            }.frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
        }
    }
}

private struct HexagramSelection: Identifiable {
    let id = UUID()
    let title: String
    let marked: HeluoMarkedHexagram
    let period: HeluoPeriodHexagram?
    let zone: String
}

struct PersonalHexagramsWorkspace: View {
    @ObservedObject var store: AppStore
    let profile: BirthProfile
    @State private var referenceHour = 12
    @State private var selection: HexagramSelection?
    private var instant: Date { store.calendar.gregorian.date(bySettingHour: referenceHour, minute: 0, second: 0, of: store.selectedDate) ?? store.selectedNoon }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("我的先后天与年月日卦").font(.system(size: 23, weight: .medium, design: .serif))
                    Text("点击卦卡，查看卦象、爻位与对应时段").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Picker("北京时间参考", selection: $referenceHour) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }.frame(width: 180)
            }
            switch store.personalHexagrams(for: profile, at: instant) {
            case .failure(let error):
                Card { Label(error.localizedDescription, systemImage: "info.circle").font(.system(size: 13)).foregroundStyle(Theme.secondary) }
            case .success(let report):
                HStack(alignment: .top, spacing: 16) {
                    natalTile("先天卦", marked: report.xianTian, zone: report.timeZoneIdentifier)
                    natalTile("后天卦", marked: report.houTian, zone: report.timeZoneIdentifier)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), alignment: .leading, spacing: 14) {
                    if let year = report.year { periodTile("值年卦", period: year, zone: report.timeZoneIdentifier) }
                    if let month = report.month { periodTile("值月卦", period: month, zone: report.timeZoneIdentifier) }
                    if let day = report.day { periodTile("值日卦", period: day, zone: report.timeZoneIdentifier) }
                }
                if let issue = report.flowUnavailableReason { Card { Text(issue).font(.system(size: 12)).foregroundStyle(Theme.secondary) } }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("计算依据与时间口径").font(.system(size: 16, weight: .medium, design: .serif))
                        Text("天数 \(report.tianNumber) · 地数 \(report.diNumber) · 立春岁序 \(report.nominalAge)").font(.system(size: 12)).foregroundStyle(Theme.accent)
                        Text("参考瞬间：" + HeluoDateText.format(instant, zone: report.timeZoneIdentifier) + " · " + report.timeZoneIdentifier)
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Text(HeluoEngine.methodNote).font(.system(size: 12)).lineSpacing(5)
                        DisclosureGroup("查看规则与边界说明") {
                            Text(report.methodNotes.joined(separator: "\n\n")).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4).padding(.top, 12)
                        }.font(.system(size: 12))
                        if let current = report.currentLifeSegment {
                            Text("当前河洛爻段：\(current.phase) · \(current.marked.lineLabel) · \(current.startAge)–\(current.endAge) 立春岁序")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        Text("河洛爻段与八字十年大运是两套规则，卦象只作传统辅助视角。配色和灵宠由你自由选择，不据卦象自动改动日程或喜用神。")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(4)
                        HStack {
                            Text(HeluoEngine.sourceTitle).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            Spacer(); Button("交给我的 Agent 解读") {
                                store.prepareAgentTask(.daily, on: instant, referenceTime: DateText.format(instant, "HH:mm"))
                            }.buttonStyle(QuietButton()).font(.system(size: 11))
                        }
                    }
                }
            }
        }.sheet(item: $selection) { item in HexagramDetailSheet(selection: item) }
    }
    private func natalTile(_ title: String, marked: HeluoMarkedHexagram, zone: String) -> some View {
        Button { selection = HexagramSelection(title: title, marked: marked, period: nil, zone: zone) } label: {
            Card {
                HStack(spacing: 26) {
                    HexagramDrawing(marked: marked, width: 66).padding(.trailing, 8)
                    VStack(alignment: .leading, spacing: 9) {
                        Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        Text(marked.hexagram.name).font(.system(size: 27, design: .serif))
                        Text("元堂 · " + marked.lineLabel).font(.system(size: 11)).foregroundStyle(Theme.accent)
                        Text(marked.hexagram.theme).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 8)
            }
        }.buttonStyle(.plain)
    }
    private func periodTile(_ title: String, period: HeluoPeriodHexagram, zone: String) -> some View {
        Button { selection = HexagramSelection(title: title, marked: period.marked, period: period, zone: zone) } label: {
            Card {
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Text(title).font(.system(size: 12, weight: .medium)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Theme.accent) }
                    HexagramDrawing(marked: period.marked, width: 61).padding(.vertical, 6)
                    Text(period.marked.hexagram.name).font(.system(size: 26, design: .serif))
                    Text(period.marked.lineLabel + " · " + period.marked.hexagram.theme).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    Text(period.periodLabel).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }.frame(maxWidth: .infinity, minHeight: 204, alignment: .topLeading)
            }
        }.buttonStyle(.plain)
    }
}

private enum HeluoDateText {
    static func format(_ date: Date, zone: String, includesSeconds: Bool = false) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: zone); f.dateFormat = includesSeconds ? "yyyy年M月d日 HH:mm:ss" : "yyyy年M月d日 HH:mm"
        return f.string(from: date)
    }
}

private struct HexagramDetailSheet: View {
    let selection: HexagramSelection
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let marked = selection.marked
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(selection.title).font(.system(size: 14)).foregroundStyle(Theme.secondary); Spacer(); Button("完成") { dismiss() }.buttonStyle(QuietButton()) }
            HStack(spacing: 35) {
                HexagramDrawing(marked: marked, width: 100).padding(.trailing, 10)
                VStack(alignment: .leading, spacing: 10) {
                    Text(marked.hexagram.name).font(.system(size: 39, weight: .medium, design: .serif))
                    Text("第 \(marked.hexagram.number) 卦 · 上\(marked.hexagram.upper)下\(marked.hexagram.lower)").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Pill(text: marked.lineLabel, color: Theme.accent)
                }
            }.padding(.vertical, 10)
            Text(marked.hexagram.theme).font(.system(size: 20, design: .serif)).foregroundStyle(Theme.accent)
            Text(marked.hexagram.reflection).font(.system(size: 14)).lineSpacing(6)
            Text("上面的文字是应用整理的反思提示；卦名与爻位来自确定的河洛规则。爻从下往上读，色点标出当前爻位。").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
            if let period = selection.period {
                Divider().overlay(Theme.line)
                Text("对应时间 · " + selection.zone).font(.system(size: 12, weight: .medium))
                Text(HeluoDateText.format(period.start, zone: selection.zone, includesSeconds: true) + " → " + HeluoDateText.format(period.end, zone: selection.zone, includesSeconds: true))
                    .font(.system(size: 12)).textSelection(.enabled)
                Text("含开始、不含结束。值日卦按六日一卦递进，爻位随自然日变化；交节瞬间归入新节月。").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
            }
            Spacer(minLength: 0)
            Text("卦象帮助整理思路，不预告确定事件。实际选择以信息、准备和现实条件为依据。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }.padding(30).frame(width: 580, height: 570).background(Theme.paper)
    }
}
