import SwiftUI
import LingxiCore

enum BaziPage: String, CaseIterable, Identifiable {
    case natal = "我的命盘", luck = "大运流年", daily = "每日解读", almanac = "黄历时辰"
    var id: String { rawValue }
}

struct BaziWorkspaceView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var profiles: BirthProfileStore
    @State private var editingProfile: BirthProfile?
    @State private var deletingProfile: BirthProfile?
    @State private var referenceHour = 12
    @State private var referenceMinute = 0
    private let engine = FourPillarsEngine()

    private var boundary: BirthDayBoundary { profiles.activeProfile?.dayBoundary ?? .midnight }
    private var referenceProfile: BirthProfile {
        let parts = store.calendar.gregorian.dateComponents([.year, .month, .day], from: store.selectedDate)
        return BirthProfile(birthYear: parts.year!, birthMonth: parts.month!, birthDay: parts.day!,
            birthHour: referenceHour, birthMinute: referenceMinute, birthTimeKnown: true,
            timeZoneIdentifier: store.calendar.gregorian.timeZone.identifier, dayBoundary: boundary)
    }
    private var daily: Result<FourPillarsChart, Error> {
        Result {
            guard let instant = try referenceProfile.resolvedBirthDate() else { throw FourPillarsError.invalidInstant }
            return try engine.chart(at: instant, timeZone: store.calendar.gregorian.timeZone, dayBoundary: boundary)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            heading.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 16)
            Picker("八字与日历内容", selection: $store.baziPage) {
                ForEach(BaziPage.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 28).padding(.bottom, 16)
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                profileCard
                switch store.baziPage {
                case .natal:
                    if let profile = profiles.activeProfile { natalContent(profile) }
                    else { dailyCard }
                case .luck:
                    if let profile = profiles.activeProfile {
                        LuckCyclesView(store: store, profile: profile) { editingProfile = profile }
                    } else { Card { Text("建立出生档案后，可以查看自己的起运、大运和流年。").font(.system(size: 13)) } }
                case .daily:
                    dailyCard
                    if let profile = profiles.activeProfile,
                       let charts = try? engine.natalCharts(for: profile), charts.count == 1,
                       let natal = charts.first, case .success(let flow) = daily {
                        PersonalReadingView(natal: natal, flow: flow, strength: profile.strengthAssumption ?? .unspecified).id(profile.id)
                    } else {
                        Card { Text(profiles.activeProfile == nil ? "建立个人档案，让这一天的干支与你的日主联系起来。" : "出生资料或参考时刻尚未形成唯一命盘；请核对上面的提示，再查看个人解读。")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                    }
                case .almanac: AlmanacWorkspaceView(store: store)
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "book.closed").foregroundStyle(Theme.jade)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("把传统当作认识自己的一扇窗").font(.system(size: 13, design: .serif))
                        Text("四柱按确定的历法规则计算；十神、合冲是传统解释。实际安排仍以准备、沟通与现实条件为依据。")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Button("查看排盘口径与来源") { store.showingSources = true }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.jade)
                    }
                    Spacer()
                }.padding(18).background(Theme.softJade.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                }.padding(28)
            }.id(store.baziPage)
        }
        .sheet(item: $editingProfile) { BirthProfileEditor(profiles: profiles, draft: $0) }
        .confirmationDialog("删除出生档案？", isPresented: Binding(get: { deletingProfile != nil }, set: { if !$0 { deletingProfile = nil } })) {
            if let profile = deletingProfile {
                Button("删除「\(profile.name)」", role: .destructive) { profiles.delete(profile); deletingProfile = nil }
            }
        } message: { Text("删除后无法恢复。这不会影响你的日程。") }
    }

    private var heading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("四柱与我的八字").font(.system(size: 27, weight: .medium, design: .serif))
                Text("读懂时序，也留意自己的节奏").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button { store.select(store.calendar.gregorian.date(byAdding: .day, value: -1, to: store.selectedDate)!) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(QuietButton()).accessibilityLabel("四柱前一天")
            DateJumpButton(store: store, title: DateText.format(store.selectedDate, "yyyy年M月d日"))
            Button { store.select(store.calendar.gregorian.date(byAdding: .day, value: 1, to: store.selectedDate)!) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(QuietButton()).accessibilityLabel("四柱后一天")
            Button("今天") { store.select(Date()) }.buttonStyle(QuietButton())
        }
    }

    private var dailyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(DateText.format(store.selectedDate, "yyyy年M月d日 · EEEE"))
                            .font(.system(size: 20, weight: .medium, design: .serif))
                        Text("农历\(store.calendar.info(for: store.selectedDate).lunarDate) · 北京时间 · \(boundary.label)")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Text("参考时刻").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Picker("参考小时", selection: $referenceHour) { ForEach(0..<24) { Text(String(format: "%02d", $0)).tag($0) } }.labelsHidden().frame(width: 63)
                        Text(":")
                        Picker("参考分钟", selection: $referenceMinute) { ForEach(0..<60) { Text(String(format: "%02d", $0)).tag($0) } }.labelsHidden().frame(width: 63)
                    }
                }
                switch daily {
                case .success(let chart):
                    FourPillarsRow(chart: chart)
                    HStack(alignment: .top) {
                        Label("立春换年 · 按十二节交接时刻换月", systemImage: "sun.horizon")
                        Spacer()
                        Text("下一节：\(chart.nextJie.name) 约\(DateText.format(Date(timeIntervalSince1970: (chart.nextJie.date.timeIntervalSince1970 / 60).rounded() * 60), "M月d日 HH:mm"))")
                    }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Text("时柱随时刻变化；上面的四柱对应所选参考时刻。交节当天，年柱或月柱也可能在日内变化。")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    if (try? referenceProfile.isBirthTimeAmbiguous()) == true {
                        Text(BirthProfile.repeatedTimePolicyDescription).font(.system(size: 10)).foregroundStyle(Theme.vermilion)
                    }
                    if nearJie(chart) { boundaryWarning }
                case .failure(let error): errorText(error.localizedDescription)
                }
            }
        }
    }

    private var profileCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("我的出生档案", systemImage: "person.crop.square").font(.system(size: 15, weight: .medium))
                    Spacer()
                    Pill(text: "仅保存在本机")
                    Button { editingProfile = BirthProfile() } label: { Label("新建档案", systemImage: "plus") }
                        .buttonStyle(QuietButton()).font(.system(size: 11)).disabled(profiles.isReadOnly)
                }
                if let error = profiles.error { errorText(error) }
                if profiles.profiles.isEmpty {
                    Text("填写公历生日、出生时间和时区，即可查看自己的八字，以及选中这一天与你的传统干支关系。时间不详也可以先建档。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                    Button("建立第一份档案") { editingProfile = BirthProfile() }.buttonStyle(JadeButton()).disabled(profiles.isReadOnly)
                } else {
                    HStack {
                        Picker("当前档案", selection: $profiles.activeID) {
                            Text("请选择档案").tag(nil as UUID?)
                            ForEach(profiles.profiles) { Text($0.name).tag(Optional($0.id)) }
                        }.frame(maxWidth: 300)
                        Spacer()
                        if let profile = profiles.activeProfile {
                            Button("编辑") { editingProfile = profile }.buttonStyle(QuietButton())
                            Button("删除") { deletingProfile = profile }.buttonStyle(.plain).foregroundStyle(Theme.vermilion)
                        }
                    }.font(.system(size: 12))
                    if let profile = profiles.activeProfile {
                        Text(profileDescription(profile)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func natalContent(_ profile: BirthProfile) -> some View {
        let result = Result { try engine.natalCharts(for: profile) }
        switch result {
        case .failure(let error): Card { errorText(error.localizedDescription) }
        case .success(let charts):
            Card {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Text("\(profile.name)的八字盘").font(.system(size: 19, weight: .medium, design: .serif))
                        Spacer()
                        if let chart = charts.first, charts.count == 1 { Pill(text: "日主 · \(chart.day.stem)\(PillarAppearance.stemElement(chart.day.stemIndex))") }
                    }
                    if !profile.birthTimeKnown {
                        Label(charts.count > 1 ? "出生时间不详，以下有 \(charts.count) 种可能；补充时刻后才能确认。" : "出生时间不详，暂列三柱，不补造时柱。", systemImage: "clock.badge.questionmark")
                            .font(.system(size: 11)).foregroundStyle(Theme.vermilion)
                    }
                    ForEach(Array(charts.enumerated()), id: \.offset) { index, chart in
                        if charts.count > 1 { Text("可能 \(index + 1)").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                        NatalChartTable(chart: chart)
                        if profile.birthTimeKnown && nearJie(chart) { boundaryWarning }
                    }
                    Text("\(profile.dayBoundary.label) · 出生地当地钟表时间 · 暂不校正真太阳时")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    if (try? profile.isBirthTimeAmbiguous()) == true {
                        Text(BirthProfile.repeatedTimePolicyDescription).font(.system(size: 10)).foregroundStyle(Theme.vermilion)
                    }
                }
            }
        }
    }

    private func profileDescription(_ profile: BirthProfile) -> String {
        let time = profile.birthTimeKnown ? String(format: "%02d:%02d", profile.birthHour, profile.birthMinute) : "时间不详"
        return "公历 \(profile.birthYear)年\(profile.birthMonth)月\(profile.birthDay)日 · \(time) · \(profile.timeZoneIdentifier)" + (profile.birthplace.isEmpty ? "" : " · \(profile.birthplace)")
    }
    private func errorText(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Theme.vermilion).textSelection(.enabled)
    }
    private func nearJie(_ chart: FourPillarsChart) -> Bool {
        min(abs(chart.instant.timeIntervalSince(chart.previousJie.date)), abs(chart.instant.timeIntervalSince(chart.nextJie.date))) < 120
    }
    private var boundaryWarning: some View {
        Label("时刻接近交节（前后 2 分钟内），计算精度或出生记录误差可能改变年／月柱，请核对记录。", systemImage: "clock.badge.exclamationmark")
            .font(.system(size: 11)).foregroundStyle(Theme.vermilion)
    }
    @ViewBuilder private func sourceLink(_ title: String, url: String) -> some View {
        if let url = URL(string: url) { Link("来源：\(title) ↗", destination: url).font(.system(size: 10)).foregroundStyle(Theme.jade) }
    }
}

enum PillarAppearance {
    static func stemElement(_ index: Int) -> String { ["木", "火", "土", "金", "水"][index / 2] }
    static func branchElement(_ index: Int) -> String { ["水", "土", "木", "木", "土", "火", "火", "土", "金", "金", "土", "水"][index] }
    static func color(_ element: String) -> Color {
        switch element { case "木": Theme.jade; case "火": Theme.vermilion; case "土": Color(hex: 0x9B804B); case "金": Color(hex: 0x8B8299); default: Color(hex: 0x4E7790) }
    }
}

struct FourPillarsRow: View {
    let chart: FourPillarsChart
    var dayMaster: Int?
    var body: some View {
        HStack(spacing: 12) {
            pillar("年柱", value: chart.year)
            pillar("月柱", value: chart.month)
            pillar("日柱", value: chart.day, isDay: true)
            pillar("时柱", value: chart.hour)
        }
    }
    private func pillar(_ title: String, value: Ganzhi?, isDay: Bool = false) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            if let value {
                HStack(spacing: 8) {
                    Text(value.stem).foregroundStyle(PillarAppearance.color(PillarAppearance.stemElement(value.stemIndex)))
                    Text(value.branch).foregroundStyle(PillarAppearance.color(PillarAppearance.branchElement(value.branchIndex)))
                }.font(.system(size: 33, weight: .medium, design: .serif))
                Text("\(PillarAppearance.stemElement(value.stemIndex)) · \(PillarAppearance.branchElement(value.branchIndex))")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary).help("天干五行 · 地支本气五行；不是全盘五行强弱")
                if let dayMaster {
                    Text(isDay ? "日主" : tenGod(dayMaster: dayMaster, other: value))
                        .font(.system(size: 11)).foregroundStyle(Theme.jade)
                }
            } else {
                Text("—").font(.system(size: 33, weight: .light, design: .serif)).foregroundStyle(Theme.secondary)
                Text("时刻不详").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                if dayMaster != nil { Text("不推算").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(isDay && dayMaster != nil ? Theme.softJade : Theme.paper, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
    }
    private func tenGod(dayMaster: Int, other: Ganzhi) -> String {
        (try? BaziRelationshipEngine().tenGod(dayMasterStemIndex: dayMaster, otherStemIndex: other.stemIndex).label) ?? ""
    }
}

struct DailyPillarsCard: View {
    @ObservedObject var store: AppStore
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("我的日笺").font(.system(size: 13, weight: .medium, design: .serif)); Spacer(); Pill(text: "历法与个人关系") }
                let noon = store.calendar.gregorian.date(bySettingHour: 12, minute: 0, second: 0, of: store.selectedDate)!
                if let chart = try? FourPillarsEngine().chart(at: noon, timeZone: store.calendar.gregorian.timeZone, dayBoundary: store.birthProfiles.activeProfile?.dayBoundary ?? .midnight) {
                    Text("\(chart.year.text)年 · \(chart.month.text)月 · \(chart.day.text)日")
                        .font(.system(size: 13, design: .serif)).foregroundStyle(Theme.jade)
                    Text("正午参考 · 年月按交节时刻切换").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                    if let natal = store.activeNatalChart,
                       let report = try? PersonalDailyReadingEngine().analyze(natal: natal, flow: chart, strength: store.birthProfiles.activeProfile?.strengthAssumption ?? .unspecified),
                       let day = report.periods.last {
                        Divider().overlay(Theme.line)
                        HStack(alignment: .firstTextBaseline) {
                            Text(day.tenGod.label).font(.system(size: 25, weight: .medium, design: .serif)).foregroundStyle(Theme.jade)
                            Spacer()
                            Text("日主 · " + report.dayMaster).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                        Text(day.theme).font(.system(size: 12, weight: .medium))
                        Text("当下月令：\(report.flowMonth.pillar.branch)月 · \(report.flowMonth.relationship)").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        Text(day.action).font(.system(size: 11)).lineSpacing(4)
                    } else if store.birthProfiles.activeProfile != nil {
                        Text("命盘仍有多个可能，补充出生时刻后查看个人关系。").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
                Button { store.baziPage = .daily; store.section = "四柱与八字" } label: {
                    HStack { Text(store.birthProfiles.activeProfile == nil ? "查看四柱 · 建立个人档案" : "展开这一天的个人解读"); Spacer(); Image(systemName: "arrow.up.right") }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.jade)
                Divider().overlay(Theme.line)
                if let day = try? AlmanacEngine.shared.day(on: store.selectedDate) {
                    Text("传统宜 · " + day.yi.prefix(5).joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
                Button { store.baziPage = .almanac; store.section = "四柱与八字" } label: {
                    HStack { Text("黄历 · 节气 · 时辰宜忌"); Spacer(); Image(systemName: "arrow.up.right") }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.jade)
            }
        }
    }
}
