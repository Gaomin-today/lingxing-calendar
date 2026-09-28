import SwiftUI
import LingxiCore

/// A compact date-detail卦象 card. The query instant is always the selected
/// civil date at Beijing 12:00; the profile's birth time zone remains visible
/// because it is part of the natal chart calculation.
struct DayHexagramCard: View {
    @ObservedObject var store: AppStore

    private var selectedDateLabel: String { DateText.day(store.selectedDate) }
    private var queryInstant: Date { store.selectedNoon }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("所选日期的卦象").font(.system(size: 14, weight: .medium, design: .serif))
                    Spacer(minLength: 0)
                    Pill(text: "北京 12:00", color: Theme.accent)
                }
                Text(selectedDateLabel + " · 不是固定的‘今日卦’")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                if let profile = store.birthProfiles.activeProfile {
                    switch store.personalHexagrams(for: profile, at: queryInstant) {
                    case .failure(let error):
                        Label(error.localizedDescription, systemImage: "info.circle")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
                    case .success(let report):
                        reportContent(report, profile: profile)
                    }
                } else {
                    missingProfile
                }
                Button {
                    store.section = "四柱与八字"
                    store.baziPage = .hexagrams
                } label: {
                    HStack(spacing: 5) { Text("查看完整先后天与年月日卦"); Image(systemName: "arrow.up.right") }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.jade)
                        .frame(minHeight: 28, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private var missingProfile: some View {
        Label("先建立个人档案，才可以把这一天放进你的出生时区规则里。", systemImage: "person.crop.circle.badge.plus")
            .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
    }

    @ViewBuilder
    private func reportContent(_ report: HeluoReport, profile: BirthProfile) -> some View {
        if let day = report.day {
            HStack(spacing: 14) {
                HexagramDrawing(marked: day.marked, width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.marked.hexagram.name).font(.system(size: 25, weight: .medium, design: .serif)).foregroundStyle(Theme.jade)
                    Text("值日 · \(day.marked.lineLabel)").font(.system(size: 10)).foregroundStyle(Theme.accent)
                    Text(day.marked.hexagram.theme).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
            }
            Text(day.marked.hexagram.reflection).font(.system(size: 10)).lineSpacing(3).lineLimit(3)
        } else {
            Text(report.xianTian.hexagram.name + " · 先天卦").font(.system(size: 20, design: .serif))
            Text(report.flowUnavailableReason ?? "该时段暂无值日卦。").font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(3)
        }
        VStack(alignment: .leading, spacing: 3) {
            Text("查询口径：北京时间 \(DateText.format(queryInstant, "yyyy年M月d日 HH:mm"))")
            Text("出生时区：\(profile.timeZoneIdentifier) · 排盘沿用当地钟表时间")
            if report.timeZoneIdentifier != "Asia/Shanghai" {
                Text("档案时区与北京不同，交节和日界可能出现差异。")
            }
        }.font(.system(size: 9)).foregroundStyle(Theme.secondary).lineSpacing(2)
    }
}
