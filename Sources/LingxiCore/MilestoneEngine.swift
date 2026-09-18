import Foundation
import LunarSwift

public enum MilestoneStatus: String, Codable, Sendable { case upcoming, today, past }
public enum MilestoneSource: String, Codable, Sendable { case milestone, birthday }

public struct MilestoneOccurrence: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let source: MilestoneSource
    public let sourceID: UUID
    public let title: String
    public let kindLabel: String
    public let targetDate: String
    /// Beijing noon on the date; usable as a calendar navigation destination.
    public let date: Date
    public let daysDelta: Int
    public let status: MilestoneStatus
    public let headline: String
    public let detail: String
    public let ruleNote: String?
}

public struct MilestoneEngine: Sendable {
    public static let timeZoneNote = "按首页北京时间的公历自然日计算，不受 Mac 所在时区影响。显示在首页倒计时，不发送系统通知。"
    public static let solarLeapDayNote = "每年重复时，2 月 29 日在非闰年按 2 月 28 日。"
    public init() {}

    public func occurrence(for milestone: Milestone, on selectedDate: Date) throws -> MilestoneOccurrence {
        try milestone.validate()
        let today = try MilestoneCivilDate(instant: selectedDate)
        let original = try MilestoneCivilDate(text: milestone.targetDate)
        let target = milestone.repeatsAnnually ? try nextSolar(month: original.month, day: original.day,
            notBefore: max(today, original), originalYear: original.year) : original
        let delta = today.days(to: target)
        let headline: String
        if delta == 0 { headline = milestone.kind == .anniversary ? "纪念日就在今天" : "就是今天" }
        else if delta > 0 { headline = "还有 \(delta) 天" }
        else { headline = milestone.kind == .anniversary ? "已经 \(-delta) 天" : "已过 \(-delta) 天" }
        let frequency = milestone.repeatsAnnually ? "每年重复" : "单次日期"
        return MilestoneOccurrence(id: "milestone-\(milestone.id)", source: .milestone, sourceID: milestone.id,
            title: milestone.title, kindLabel: milestone.kind.label, targetDate: target.text, date: target.noon,
            daysDelta: delta, status: Self.status(delta), headline: headline,
            detail: "\(target.text) · \(frequency)" + (milestone.note.isEmpty ? "" : " · \(milestone.note)"),
            ruleNote: milestone.repeatsAnnually && original.month == 2 && original.day == 29 ? Self.solarLeapDayNote : nil)
    }

    /// Unselected or not-yet-born profiles never silently create birthday entries.
    /// Birthday dates use the *recorded civil birth date*, not an inferred instant;
    /// unknown birth hour therefore does not prevent tracking a birthday.
    public func birthday(for profile: BirthProfile, on selectedDate: Date) throws -> MilestoneOccurrence? {
        guard let tracking = profile.birthdayTracking else { return nil }
        try profile.validate()
        let today = try MilestoneCivilDate(instant: selectedDate)
        let birth = try MilestoneCivilDate(year: profile.birthYear, month: profile.birthMonth, day: profile.birthDay)
        guard today >= birth else { return nil }
        let target: MilestoneCivilDate, originalLabel: String, adjustment: String?
        if tracking == .solar {
            target = try nextSolar(month: birth.month, day: birth.day, notBefore: today, originalYear: birth.year)
            originalLabel = "公历 \(birth.month) 月 \(birth.day) 日"
            adjustment = birth.month == 2 && birth.day == 29 && target.day == 28 ? "今年非闰年，按 2 月 28 日" : nil
        } else {
            let result = try nextLunarBirthday(birth: birth, today: today)
            target = result.target; originalLabel = result.label; adjustment = result.adjustment
        }
        let delta = today.days(to: target)
        return MilestoneOccurrence(id: "birthday-\(profile.id)", source: .birthday, sourceID: profile.id,
            title: "\(profile.name)的生日", kindLabel: tracking.label, targetDate: target.text, date: target.noon,
            daysDelta: delta, status: Self.status(delta), headline: delta == 0 ? "生日就在今天" : "还有 \(delta) 天",
            detail: "\(target.text) · \(originalLabel)" + (adjustment.map { " · " + $0 } ?? ""),
            ruleNote: tracking.ruleNote)
    }

    public func civilDate(_ text: String) throws -> Date { try MilestoneCivilDate(text: text).noon }
    public func dateText(_ date: Date) throws -> String { try MilestoneCivilDate(instant: date).text }

    public static func sorted(_ entries: [MilestoneOccurrence]) -> [MilestoneOccurrence] {
        entries.sorted { lhs, rhs in
            let left = lhs.daysDelta < 0 ? 1 : 0, right = rhs.daysDelta < 0 ? 1 : 0
            if left != right { return left < right }
            if lhs.daysDelta != rhs.daysDelta { return left == 0 ? lhs.daysDelta < rhs.daysDelta : lhs.daysDelta > rhs.daysDelta }
            return lhs.id < rhs.id
        }
    }

    private static func status(_ delta: Int) -> MilestoneStatus { delta == 0 ? .today : delta < 0 ? .past : .upcoming }
    private func nextSolar(month: Int, day: Int, notBefore today: MilestoneCivilDate, originalYear: Int) throws -> MilestoneCivilDate {
        for year in max(today.year, originalYear)...2099 {
            let leap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
            let observedDay = month == 2 && day == 29 && !leap ? 28 : day
            let candidate = try MilestoneCivilDate(year: year, month: month, day: observedDay)
            if candidate >= today { return candidate }
        }
        throw MilestoneError.noNextOccurrence
    }

    private func nextLunarBirthday(birth: MilestoneCivilDate, today: MilestoneCivilDate) throws -> (target: MilestoneCivilDate, label: String, adjustment: String?) {
        try LunarRuntimeAccess.withLock {
            let original = Solar.fromYmdHms(year: birth.year, month: birth.month, day: birth.day, hour: 12).lunar
            let current = Solar.fromYmdHms(year: today.year, month: today.month, day: today.day, hour: 12).lunar
            let month = original.month, day = original.day
            let label = "农历" + original.monthInChinese + "月" + original.dayInChinese
            // At most two lunar years are needed under the declared fallback,
            // but include a padding year safely and reject any Gregorian 2100 date.
            for year in current.year...min(current.year + 2, 2099) {
                let lunarYear = LunarYear.fromYear(lunarYear: year)
                let hasSameLeap = month < 0 && lunarYear.leapMonth == abs(month)
                let observedMonth = hasSameLeap ? month : abs(month)
                guard let lunarMonth = lunarYear.getMonth(lunarMonth: observedMonth) else { continue }
                let observedDay = min(day, lunarMonth.dayCount)
                let solar = Lunar.fromYmdHms(lunarYear: year, lunarMonth: observedMonth, lunarDay: observedDay, hour: 12).solar
                guard BirthProfile.supportedYears.contains(solar.year) else { continue }
                let target = try MilestoneCivilDate(year: solar.year, month: solar.month, day: solar.day)
                guard target >= today else { continue }
                var changes: [String] = []
                if month < 0 && !hasSameLeap { changes.append("今年无对应闰月，按普通\(abs(month))月") }
                if observedDay != day { changes.append("当月只有\(observedDay)日，按月末日") }
                return (target, label, changes.isEmpty ? nil : changes.joined(separator: "；"))
            }
            throw MilestoneError.noNextOccurrence
        }
    }
}
