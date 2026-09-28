import SwiftUI
import LingxiCore

struct StrengthAnalysisCard: View {
    @ObservedObject var store: AppStore
    let profile: BirthProfile
    var body: some View {
        let report = store.nativeStrength(for: profile)
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("我的旺衰初判").font(.system(size: 19, weight: .medium, design: .serif))
                        Text(report.ruleName).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(); Pill(text: report.label, color: Theme.accent)
                }
                Text(report.summary).font(.system(size: 13)).lineSpacing(5)
                if !report.uncertainties.isEmpty {
                    Label(report.uncertainties.joined(separator: "\n"), systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
                }
                HStack {
                    Text("每日解读采用：" + store.strength(for: profile).label).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(store.strengthSource(for: profile)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }.padding(12).background(Theme.softJade, in: RoundedRectangle(cornerRadius: 9))
                if let note = store.dayNotes.latestAssessment(for: profile) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.title).font(.system(size: 12))
                            Text("Agent 分析 · 与当前出生资料一致").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                        Spacer(); Button("查看 Agent 依据") { store.open(note: note) }.buttonStyle(QuietButton()).font(.system(size: 11))
                    }
                }
                DisclosureGroup("本地判断依据 · \(report.evidence.count) 组线索") {
                    VStack(alignment: .leading, spacing: 17) {
                        ForEach(report.evidence) { evidence in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(evidence.title).font(.system(size: 13, weight: .medium))
                                    Spacer(); Text(direction(evidence.direction)).font(.system(size: 10)).foregroundStyle(Theme.accent)
                                }
                                ForEach(Array(evidence.observations.enumerated()), id: \.offset) { _, item in Text(item).font(.system(size: 12)).lineSpacing(4) }
                                Text(evidence.ruleNote).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(3)
                            }
                        }
                        if !report.counterEvidence.isEmpty {
                            Text("同时保留的相反线索").font(.system(size: 13, weight: .medium))
                            Text(report.counterEvidence.joined(separator: "\n")).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                        }
                        Text(report.limitations.joined(separator: "\n")).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(4)
                    }.padding(.top, 14)
                }.font(.system(size: 12))
                HStack {
                    Button { store.prepareAgentTask(.natal) } label: { Label("交给我的 Agent 深入复核", systemImage: "sparkles") }.buttonStyle(QuietButton()).font(.system(size: 11))
                    Spacer()
                    if let url = URL(string: report.sourceURL) { Link("藏干算法来源 ↗", destination: url).font(.system(size: 10)).foregroundStyle(Theme.jade) }
                }
                Text(report.scopeNote).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(3)
            }
        }
    }
    private func direction(_ value: StrengthEvidenceDirection) -> String {
        switch value { case .strong: return "生扶线索"; case .weak: return "泄耗克线索"; case .mixed: return "需要综合"; case .neutral: return "盘面事实" }
    }
}
