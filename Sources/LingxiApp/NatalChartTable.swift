import SwiftUI
import LingxiCore

struct ExplanationButton: View {
    let title: String
    let explanation: String
    var sourceTitle: String = NatalChartDetailsEngine.sourceTitle
    var sourceURL: String = NatalChartDetailsEngine.sourceURL
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 4) { Text(title); Image(systemName: "info.circle").font(.system(size: 9)).opacity(0.65) }
        }.buttonStyle(.plain).foregroundStyle(Theme.jade).accessibilityLabel("解释\(title)")
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 13) {
                    Text(title).font(.system(size: 20, weight: .medium, design: .serif))
                    Text(explanation).font(.system(size: 13)).lineSpacing(5).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let url = URL(string: sourceURL) {
                        Link(sourceTitle + " ↗", destination: url).font(.system(size: 11)).foregroundStyle(Theme.jade)
                    }
                }.padding(23).frame(width: 350).background(Theme.paper)
            }
    }
}

struct NatalChartTable: View {
    let chart: FourPillarsChart
    private var details: NatalChartDetails { NatalChartDetailsEngine().details(for: chart) }
    var body: some View {
        VStack(spacing: 0) {
            row(title: "四柱", explanation: "年、月、日、时各由一个天干与地支组成。日柱的天干称日主或日元，是比较十神关系的参照。年柱在立春交接，月柱在十二节交接。") { item in
                VStack(spacing: 10) {
                    Text(item.label).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    HStack(spacing: 9) {
                        Text(item.pillar.stem).foregroundStyle(PillarAppearance.color(item.stemElement))
                        Text(item.pillar.branch).foregroundStyle(PillarAppearance.color(item.branchElement))
                    }.font(.system(size: 35, weight: .medium, design: .serif))
                    Text(item.stemElement + " · " + item.branchElement).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }.padding(.vertical, 6)
            }
            row(title: "主星", explanation: "主星是本柱天干相对日主的十神名称，由五行生克和阴阳同异决定。日柱天干本身标为日主；十神不是吉凶等级。") { item in
                if item.id == "day" {
                    Text("日主").font(.system(size: 12, weight: .medium))
                } else {
                    let reading = try? BaziRelationshipEngine().tenGod(dayMasterStemIndex: chart.day.stemIndex, otherStemIndex: item.pillar.stemIndex)
                    ExplanationButton(title: item.tenGod, explanation: reading?.explanation.replacingOccurrences(of: "流日", with: item.label) ?? "", sourceTitle: reading?.sourceTitle ?? "十神规则", sourceURL: reading?.sourceURL ?? NatalChartDetailsEngine.sourceURL)
                        .font(.system(size: 12))
                }
            }
            row(title: "藏干", explanation: "地支依固定传统规则藏有一至三个天干。第一项标本气，其余藏干依规则表顺序列出，不强行统一各流派中气、余气的分配，也不换算成精确能量比例。副星是每个藏干相对日主的十神。") { item in
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(item.hiddenStems.enumerated()), id: \.element.id) { index, stem in
                        HStack(spacing: 5) {
                            Text(stem.stem + stem.element).foregroundStyle(PillarAppearance.color(stem.element))
                            Text(stem.tenGod).foregroundStyle(Theme.ink)
                            Text(index == 0 ? "本气" : "藏干").font(.system(size: 8)).foregroundStyle(Theme.secondary)
                        }.font(.system(size: 11))
                    }
                }
            }
            row(title: "纳音", explanation: "纳音把六十甲子两两归为三十种传统名称，例如海中金、炉中火。它与天干地支本身的五行是不同层次，不能据此独立判断旺衰或喜用。") { Text($0.naYin).font(.system(size: 12)) }
            row(title: "星运", explanation: "以日主天干对每一柱地支，按阴阳顺逆计算十二长生阶段。长生、沐浴、冠带、临官、帝旺、衰、病、死、墓、绝、胎、养都是传统阶段名，不能按字面解释健康或命运。") { Text($0.dayMasterStage).font(.system(size: 12)) }
            row(title: "自坐", explanation: "自坐以该柱自己的天干对该柱地支计算十二长生；星运以日主对各地支计算。因此同一柱的星运与自坐可能不同。") { Text($0.selfStage).font(.system(size: 12)) }
            row(title: "旬 / 空亡", explanation: "六十甲子每十组为一旬；十个天干配十二地支后，未配到的两个地支称旬空。此处列各柱自身所在旬及旬空，不把一个“空”字解释为实际损失，也不代表已完成全盘空亡判定。") { item in
                VStack(spacing: 4) { Text(item.xun + "旬"); Text(item.xunKong).foregroundStyle(Theme.secondary) }.font(.system(size: 11))
            }
        }.background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func row<Content: View>(title: String, explanation: String, @ViewBuilder content: @escaping (NatalPillarDetail) -> Content) -> some View {
        HStack(spacing: 0) {
            ExplanationButton(title: title, explanation: explanation).font(.system(size: 11))
                .frame(width: 99, alignment: .leading).padding(.leading, 13)
            ForEach(0..<4, id: \.self) { index in
                Group {
                    if index < details.pillars.count { content(details.pillars[index]) }
                    else { Text(title == "四柱" ? "时柱\n时刻不详" : "—").font(.system(size: 11)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center) }
                }.frame(maxWidth: .infinity).frame(minHeight: 30)
                    .padding(.vertical, 12).background(index == 2 ? Theme.softJade.opacity(0.6) : .clear)
            }
        }.overlay(alignment: .bottom) { Rectangle().fill(Theme.line.opacity(0.65)).frame(height: 0.5) }
    }
}
