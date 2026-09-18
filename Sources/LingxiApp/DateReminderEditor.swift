import SwiftUI
import LingxiCore

/// A small, shared editor for the local reminder rule attached to a date.
/// The rule is deliberately separate from notification delivery: the app can
/// display and validate the user's intent even when macOS notifications are
/// disabled or the event is not yet scheduled by the notification service.
struct DateReminderEditor: View {
    @Binding var reminder: DateReminder?
    var title: String = "提醒"

    @State private var customDays = ""

    private enum Mode: Hashable {
        case off, today, oneDay, sevenDays, custom
    }

    private var mode: Mode {
        guard let reminder else { return .off }
        switch reminder.daysBefore {
        case 0: return .today
        case 1: return .oneDay
        case 7: return .sevenDays
        default: return .custom
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .medium))
            Picker("提醒时间", selection: Binding(get: { mode }, set: setMode)) {
                Text("关闭").tag(Mode.off)
                Text("当天").tag(Mode.today)
                Text("提前 1 天").tag(Mode.oneDay)
                Text("提前 7 天").tag(Mode.sevenDays)
                Text("自定义").tag(Mode.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if reminder != nil {
                HStack(spacing: 10) {
                    if mode == .custom {
                        TextField("天数", text: $customDays)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 65)
                            .monospacedDigit()
                            .onChange(of: customDays) { _, value in
                                guard let days = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                                reminder?.daysBefore = min(max(days, 0), 365)
                            }
                        Text("天前")
                    } else {
                        Text("提前 \(reminder?.daysBefore ?? 0) 天")
                    }
                    Spacer()
                    Text("提醒时间")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Picker("小时", selection: hourBinding) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                    }.labelsHidden().frame(width: 62)
                    Text(":").foregroundStyle(Theme.secondary)
                    Picker("分钟", selection: minuteBinding) {
                        ForEach(Array(stride(from: 0, through: 59, by: 5)), id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                    }.labelsHidden().frame(width: 62)
                }
                Text("保存提醒规则后，实际通知还受系统通知权限和提醒服务状态影响。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("默认关闭。开启后可在目标日期前收到提醒。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
        }
        .onAppear {
            customDays = reminder.map { String($0.daysBefore) } ?? ""
        }
    }

    private var hourBinding: Binding<Int> {
        Binding(get: { reminder?.hour ?? 9 }, set: { reminder?.hour = min(max($0, 0), 23) })
    }

    private var minuteBinding: Binding<Int> {
        Binding(get: { reminder?.minute ?? 0 }, set: { reminder?.minute = min(max($0, 0), 59) })
    }

    private func setMode(_ newMode: Mode) {
        switch newMode {
        case .off: reminder = nil
        case .today: reminder = DateReminder(daysBefore: 0, hour: reminder?.hour ?? 9, minute: reminder?.minute ?? 0)
        case .oneDay: reminder = DateReminder(daysBefore: 1, hour: reminder?.hour ?? 9, minute: reminder?.minute ?? 0)
        case .sevenDays: reminder = DateReminder(daysBefore: 7, hour: reminder?.hour ?? 9, minute: reminder?.minute ?? 0)
        case .custom:
            let days = min(max(Int(customDays) ?? reminder?.daysBefore ?? 3, 0), 365)
            customDays = String(days)
            reminder = DateReminder(daysBefore: days, hour: reminder?.hour ?? 9, minute: reminder?.minute ?? 0)
        }
    }
}

/// Separate sheet used from birthday management so toggling a checkbox does
/// not immediately persist a half-edited reminder rule.
struct BirthdayReminderEditor: View {
    @ObservedObject var profiles: BirthProfileStore
    let profileID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var reminder: DateReminder?
    @State private var error: String?
    private let originalRevision: String

    init(profiles: BirthProfileStore, profile: BirthProfile) {
        self.profiles = profiles
        self.profileID = profile.id
        _reminder = State(initialValue: profile.birthdayReminder)
        self.originalRevision = (try? AutomationSnapshot.revision(profile)) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("生日提醒").font(.system(size: 23, weight: .medium, design: .serif))
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(QuietButton())
            }
            if let profile = profiles.profiles.first(where: { $0.id == profileID }) {
                Text("为「\(profile.name)」设置提醒。生日显示必须先在档案中开启。")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                if profile.birthdayTracking == nil {
                    Text("这份档案尚未开启首页生日显示，请先打开生日跟踪。")
                        .font(.system(size: 12)).foregroundStyle(Theme.vermilion)
                }
                DateReminderEditor(reminder: $reminder, title: "生日提醒规则")
                    .disabled(profile.birthdayTracking == nil || profiles.isReadOnly)
            } else {
                Text("档案已不存在，请关闭此窗口。")
                    .font(.system(size: 12)).foregroundStyle(Theme.vermilion)
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Theme.vermilion) }
            HStack {
                Spacer()
                Button("保存") { save() }.buttonStyle(JadeButton())
                    .disabled(profiles.isReadOnly || profiles.profiles.first(where: { $0.id == profileID })?.birthdayTracking == nil)
            }
        }
        .padding(26).frame(width: 500).background(Theme.paper).foregroundStyle(Theme.ink)
    }

    private func save() {
        guard var current = profiles.profiles.first(where: { $0.id == profileID }) else { error = "档案已不存在。"; return }
        guard (try? AutomationSnapshot.revision(current)) == originalRevision else {
            error = "这份档案已在别处修改，请关闭后重新打开。"; return
        }
        guard current.birthdayTracking != nil else { error = "请先开启生日显示。"; return }
        current.birthdayReminder = reminder
        let active = profiles.activeID
        if profiles.save(current) { profiles.activeID = active; dismiss() }
        else { error = profiles.error }
    }
}
