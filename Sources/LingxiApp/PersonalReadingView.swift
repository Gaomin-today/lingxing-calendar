import SwiftUI
import LingxiCore

struct PersonalReadingView: View {
    let natal: FourPillarsChart
    let flow: FourPillarsChart
    let strength: BaziStrengthAssumption
    let strengthSource: String
    @State private var selection: BaziStrengthAssumption
    init(natal: FourPillarsChart, flow: FourPillarsChart, strength: BaziStrengthAssumption, strengthSource: String) {
        self.natal = natal; self.flow = flow; self.strength = strength
        self.strengthSource = strengthSource
        _selection = State(initialValue: strength)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("从你的日主，看这一天").font(.system(size: 21, weight: .medium, design: .serif))
                Spacer()
                Pill(text: "本地规则解读")
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(strengthSource).font(.system(size: 12, weight: .medium))
                        Spacer(); Pill(text: strength.label)
                    }
                    Text(strength == .unspecified ? "当前证据暂未形成明确倾向，先呈现确定的十神、月令与关系。上方可查看本地判断依据，也可交给自己的 Agent 深入复核。" : "使用与当前出生资料对应的解读前提。它属于传统分析，不等同于身体或心理强弱。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
                    DisclosureGroup("进阶：临时比较不同旺衰前提") {
                        Picker("本次阅读的旺衰前提", selection: $selection) {
                            ForEach(BaziStrengthAssumption.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().padding(.top, 10)
                        ExplanationButton(title: "旺衰解读前提", explanation: selection.explanation + "\n这里只临时比较，不改写已保存的分析。特殊格局、调候与合化需另行综合判断。", sourceTitle: PersonalDailyReadingEngine.balanceSourceTitle, sourceURL: PersonalDailyReadingEngine.balanceSourceURL).font(.system(size: 11)).padding(.top, 6)
                    }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    if selection != strength { Text("当前为临时比较：" + selection.label).font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
                }
            }
            switch Result(catching: { try PersonalDailyReadingEngine().analyze(natal: natal, flow: flow, strength: selection) }) {
            case .failure(let error): Text(error.localizedDescription).foregroundStyle(Theme.vermilion)
            case .success(let report): reading(report)
            }
        }.onChange(of: strength) { _, value in selection = value }
    }
    @ViewBuilder private func reading(_ report: PersonalDailyReadingReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(report.headline).font(.system(size: 24, weight: .medium, design: .serif))
                    Spacer(); Pill(text: "日主 · " + report.dayMaster)
                }
                Text(report.summary).font(.system(size: 13)).lineSpacing(5)
                Text(report.strengthContext).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
                if report.hasUnknownBirthHour { Label("时柱不详，以下只基于已知三柱。", systemImage: "clock.badge.questionmark").font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
            }
        }
        HStack(alignment: .top, spacing: 14) {
            monthCard(report.natalMonth)
            monthCard(report.flowMonth)
        }
        ForEach(report.periods.reversed()) { period in
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(period.title).font(.system(size: 17, weight: .medium, design: .serif))
                        Spacer()
                        ExplanationButton(title: "关系依据", explanation: period.ruleNote + "\n" + period.tenGod.explanation, sourceTitle: period.sourceTitle, sourceURL: period.sourceURL).font(.system(size: 10))
                    }
                    Text(period.theme).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.jade)
                    Text(period.explanation).font(.system(size: 12)).lineSpacing(4)
                    Text(period.conditionalInterpretation).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(5)
                    Label(period.action, systemImage: "leaf").font(.system(size: 12)).lineSpacing(4)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.softJade.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("流日与原局的合、冲、害").font(.system(size: 17, weight: .medium, design: .serif))
                    Spacer(); Pill(text: report.relationships.tendency.label, color: Theme.vermilion)
                }
                Text(report.relationships.summary).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                ForEach(report.relationships.relations) { relation in
                    HStack(alignment: .top, spacing: 16) {
                        ExplanationButton(title: relation.title, explanation: relation.explanation, sourceTitle: relation.sourceTitle, sourceURL: relation.sourceURL).font(.system(size: 12)).frame(width: 240, alignment: .leading)
                        Text(relation.reflection).font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.vertical, 5)
                }
                Text(report.relationships.reflection).font(.system(size: 12)).lineSpacing(4)
            }
        }
        Card {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 17) {
                    ForEach(report.observations) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            ExplanationButton(title: item.title, explanation: item.ruleNote, sourceTitle: item.sourceTitle, sourceURL: item.sourceURL).font(.system(size: 13))
                            Text(item.body).font(.system(size: 12)).lineSpacing(4)
                            if !item.evidence.isEmpty { Text(item.evidence.joined(separator: "；")).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                        }
                    }
                }.padding(.top, 15)
            } label: { Text("查看月令、同类与根气线索").font(.system(size: 13, weight: .medium)) }
        }
        Text(report.scopeNote).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(4)
    }
    private func monthCard(_ month: BaziMonthContext) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(month.title).font(.system(size: 13, weight: .medium)); Spacer()
                    ExplanationButton(title: "月令", explanation: month.ruleNote, sourceTitle: month.sourceTitle, sourceURL: month.sourceURL).font(.system(size: 10))
                }
                Text("\(month.pillar.text) · \(month.relationship)").font(.system(size: 20, design: .serif)).foregroundStyle(Theme.jade)
                Text("本气 \(month.mainStem)\(month.element) · \(month.tenGod.label)").font(.system(size: 12))
                Text(month.summary).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity)
    }
}
