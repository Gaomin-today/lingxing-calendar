import SwiftUI
import LingxiCore

struct BirthProfileEditor: View {
    @ObservedObject var profiles: BirthProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BirthProfile
    @State private var year: String
    @State private var month: String
    @State private var day: String
    @State private var hour: String
    @State private var minute: String
    @State private var saveError: String?
    @State private var originalRevision: String?

    init(profiles: BirthProfileStore, draft: BirthProfile = BirthProfile()) {
        self.profiles = profiles
        _originalRevision = State(initialValue: profiles.profiles.contains(where: { $0.id == draft.id }) ? try? AutomationSnapshot.revision(draft) : nil)
        _draft = State(initialValue: draft)
        _year = State(initialValue: String(draft.birthYear))
        _month = State(initialValue: String(draft.birthMonth))
        _day = State(initialValue: String(draft.birthDay))
        _hour = State(initialValue: String(format: "%02d", draft.birthHour))
        _minute = State(initialValue: String(format: "%02d", draft.birthMinute))
    }

    private struct Validation {
        var profile: BirthProfile?
        var problem: String?
        var warning: String?
    }

    private var validation: Validation {
        if let problem = BirthProfileStore.nameError(for: draft.name) { return Validation(problem: problem) }
        guard let year = integer(year), let month = integer(month), let day = integer(day) else {
            return Validation(problem: "出生年、月、日请填写完整的公历数字。")
        }
        var candidate = draft
        candidate.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.timeZoneIdentifier = draft.timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.birthYear = year; candidate.birthMonth = month; candidate.birthDay = day
        if draft.birthTimeKnown {
            guard let hour = integer(hour), let minute = integer(minute) else {
                return Validation(problem: "出生时、分请填写数字；小时使用 0–23 的 24 小时制。")
            }
            candidate.birthHour = hour; candidate.birthMinute = minute
        }
        do {
            try candidate.validate()
            let repeated = try candidate.isBirthTimeAmbiguous()
            return Validation(profile: candidate, warning: repeated ? BirthProfile.repeatedTimePolicyDescription : nil)
        } catch { return Validation(problem: error.localizedDescription) }
    }

    private var isEditing: Bool { profiles.profiles.contains { $0.id == draft.id } }

    var body: some View {
        let result = validation
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(isEditing ? "编辑出生档案" : "留下一份出生档案")
                        .font(.system(size: 24, weight: .medium, design: .serif))
                    Text("从确定的信息开始，了解流日与你的传统干支关系。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("关闭出生档案编辑器")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    identityFields
                    birthDateFields
                    locationFields
                    boundaryFields
                    interpretationFields
                    birthdayFields
                    if let problem = result.problem {
                        feedback(problem, symbol: "exclamationmark.circle", color: Theme.vermilion)
                    }
                    if let warning = result.warning {
                        feedback(warning, symbol: "clock.arrow.circlepath", color: Theme.vermilion)
                    }
                    if let error = profiles.isReadOnly ? profiles.error : saveError {
                        feedback(error, symbol: "exclamationmark.triangle", color: Theme.vermilion)
                            .textSelection(.enabled)
                    }
                    Text("档案保存在本机，随时可以编辑或删除。出生地只作备注，时区请按出生记录核对。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.trailing, 5)
            }
            HStack {
                Pill(text: "本地个人档案")
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button("保存档案") { save() }.buttonStyle(JadeButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(result.profile == nil || profiles.isReadOnly)
                    .opacity(result.profile == nil || profiles.isReadOnly ? 0.5 : 1)
            }.font(.system(size: 12))
        }
        .padding(26).frame(width: 640, height: 760)
        .background(Theme.paper).foregroundStyle(Theme.ink).preferredColorScheme(.light)
    }

    private var identityFields: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("姓名或称呼").font(.system(size: 12, weight: .medium))
                    Text("必填").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text("\(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(BirthProfileStore.maximumNameLength)")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                TextField("例如：我自己", text: $draft.name)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("姓名或称呼，必填，最多 40 个字")
            }
        }
    }

    private var birthDateFields: some View {
        Card {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("公历出生日期").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("1901–2099 年").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                HStack(alignment: .bottom, spacing: 13) {
                    numericField("年", value: $year, placeholder: "1990", width: 125)
                    numericField("月", value: $month, placeholder: "1", width: 80)
                    numericField("日", value: $day, placeholder: "1", width: 80)
                    Spacer()
                }
                Toggle("知道准确的出生时刻", isOn: $draft.birthTimeKnown)
                    .toggleStyle(.checkbox).font(.system(size: 12))
                if draft.birthTimeKnown {
                    HStack(alignment: .bottom, spacing: 13) {
                        numericField("时（0–23）", value: $hour, placeholder: "12", width: 125)
                        numericField("分（0–59）", value: $minute, placeholder: "00", width: 100)
                        Spacer()
                    }
                    Text("填写出生地当时钟表上的当地时间；历史夏令时按所选时区处理。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                } else {
                    Text("时刻未知时保留不确定性，不补造时柱。之后找到记录可以再补充。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private var locationFields: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                Text("出生时区").font(.system(size: 13, weight: .medium))
                HStack(spacing: 10) {
                    TextField("Asia/Shanghai", text: $draft.timeZoneIdentifier)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("出生时区 IANA 标识")
                    Menu("常用时区") {
                        ForEach(Self.commonZones, id: \.identifier) { zone in
                            Button("\(zone.label) · \(zone.identifier)") { draft.timeZoneIdentifier = zone.identifier }
                        }
                    }.frame(width: 105)
                }
                Text("可选择常用时区，也可填写完整 IANA 标识，如 America/New_York。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Divider().overlay(Theme.line)
                TextField("出生地备注（可选，例如：杭州）", text: $draft.birthplace)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("出生地备注，可选")
                Text("出生地不会自动推断时区，也不用于真太阳时校正。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var boundaryFields: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                Text("日柱换日方式").font(.system(size: 13, weight: .medium))
                Picker("换日方式", selection: $draft.dayBoundary) {
                    ForEach(BirthDayBoundary.allCases) { boundary in Text(boundary.label).tag(boundary) }
                }.pickerStyle(.segmented).labelsHidden()
                Text("零点按出生地当地 00:00 换日；子初按 23:00 换日。不同传统有不同口径，排盘时会标明你的选择。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("两种日柱口径下，23 点起的子时都以次日日干起时干，使 23–01 点时柱连续。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func numericField(_ label: String, value: Binding<String>, placeholder: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            TextField(placeholder, text: value).textFieldStyle(.roundedBorder)
                .monospacedDigit().accessibilityLabel("出生\(label)")
        }.frame(width: width)
    }

    private var interpretationFields: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                Text("大运与解读口径").font(.system(size: 13, weight: .medium))
                Picker("大运排法所用性别", selection: $draft.luckGender) {
                    Text("暂不填写").tag(nil as LuckGender?)
                    ForEach(LuckGender.allCases) { Text($0.label).tag(Optional($0)) }
                }.pickerStyle(.segmented)
                Text("传统顺逆排运规则需要此项和准确出生时刻；暂不填写也能查看命盘与每日关系。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Divider().overlay(Theme.line)
                DisclosureGroup("进阶：手动指定旺衰前提") {
                    Picker("旺衰解读前提", selection: Binding(get: { draft.strengthAssumption ?? .unspecified }, set: { draft.strengthAssumption = $0 })) {
                        ForEach(BaziStrengthAssumption.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).padding(.top, 10)
                    Text("通常无需填写。保持未确定时，优先采用与你当前档案匹配的 Agent 分析，否则使用本地旺衰初判；手动指定身强或身弱将优先使用此处设定。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.top, 6)
                }.font(.system(size: 12))
            }
        }
    }

    private var birthdayFields: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("首页生日倒计时").font(.system(size: 13, weight: .medium))
                Toggle("在首页显示这份档案的生日", isOn: Binding(
                    get: { draft.birthdayTracking != nil },
                    set: {
                        draft.birthdayTracking = $0 ? .solar : nil
                        if !$0 { draft.birthdayReminder = nil }
                    }
                )).toggleStyle(.checkbox).font(.system(size: 12))
                if draft.birthdayTracking != nil {
                    Picker("生日历法", selection: Binding(get: { draft.birthdayTracking ?? .solar }, set: { draft.birthdayTracking = $0 })) {
                        ForEach(BirthdayTracking.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    Text((draft.birthdayTracking ?? .solar).ruleNote).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
                    DateReminderEditor(reminder: $draft.birthdayReminder, title: "生日提醒")
                }
                Text("默认关闭。首页展示与系统通知分开控制；不改变命盘与已有分析。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
            }
        }
    }

    private func feedback(_ message: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
            Text(message).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 11)).foregroundStyle(color)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func integer(_ text: String) -> Int? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        return Int(clean)
    }

    private func save() {
        let current = profiles.profiles.first { $0.id == draft.id }
        guard (try? current.map(AutomationSnapshot.revision)) == originalRevision else {
            saveError = "这份档案已在别处修改或删除，请关闭并重新打开后编辑。"; return
        }
        guard let candidate = validation.profile else { return }
        if profiles.save(candidate) { dismiss() }
        else { saveError = profiles.error }
    }

    private struct CommonZone {
        let label: String
        let identifier: String
    }
    private static let commonZones: [CommonZone] = [
        .init(label: "北京 / 上海", identifier: "Asia/Shanghai"),
        .init(label: "香港", identifier: "Asia/Hong_Kong"),
        .init(label: "台北", identifier: "Asia/Taipei"),
        .init(label: "东京", identifier: "Asia/Tokyo"),
        .init(label: "新加坡", identifier: "Asia/Singapore"),
        .init(label: "洛杉矶", identifier: "America/Los_Angeles"),
        .init(label: "纽约", identifier: "America/New_York"),
        .init(label: "伦敦", identifier: "Europe/London"),
        .init(label: "柏林", identifier: "Europe/Berlin"),
        .init(label: "悉尼", identifier: "Australia/Sydney"),
        .init(label: "协调世界时", identifier: "UTC")
    ]
}
