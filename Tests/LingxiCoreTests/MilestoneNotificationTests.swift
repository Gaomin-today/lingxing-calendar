import Foundation
import Testing
@testable import LingxiCore

struct MilestoneNotificationTests {
    private let engine = MilestoneEngine()
    private func date(_ text: String) throws -> Date { try engine.civilDate(text) }
    private func milestone(_ title: String = "合成目标", target: String = "2026-09-25", repeat: Bool = false, reminder: DateReminder? = DateReminder()) -> Milestone {
        Milestone(title: title, targetDate: target, repeatsAnnually: `repeat`, reminder: reminder)
    }
    private func profile(tracking: BirthdayTracking? = .solar, reminder: DateReminder? = DateReminder()) -> BirthProfile {
        BirthProfile(name: "合成生日", birthYear: 1990, birthMonth: 9, birthDay: 25,
                     birthdayTracking: tracking, birthdayReminder: reminder)
    }

    @Test func configuredSourcesAndRemindersExposeStableMetadata() throws {
        let now = try date("2026-09-18")
        let item = milestone(); let person = profile()
        let plan = try MilestoneNotificationPlan(milestones: [item], profiles: [person], now: now)
        #expect(plan.sources.count == 2)
        #expect(plan.reminders.count == 2)
        #expect(plan.sources.map(\.sourceKey) == plan.sources.map(\.sourceKey).sorted())
        #expect(plan.reminders.allSatisfy { $0.fireDate >= now && $0.fireDate < plan.windowEnd })
        #expect(plan.reminders.allSatisfy { !$0.targetDate.isEmpty && $0.id.hasPrefix($0.sourceKey + "|") })
        #expect(plan.reminders.allSatisfy { MilestoneNotificationPlan.isValid($0, milestones: [item], profiles: [person]) })
        let encoded = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(MilestoneNotificationPlan.self, from: encoded) == plan)
    }

    @Test func defaultReminderIsNineAmAndLegacyNilProducesNoSource() throws {
        let value = DateReminder()
        #expect(value.daysBefore == 0 && value.hour == 9 && value.minute == 0)
        #expect(try MilestoneNotificationPlan(milestones: [Milestone(title: "无提醒", targetDate: "2026-09-25")], profiles: [profile(reminder: nil)], now: date("2026-09-18")).sources.isEmpty)
        #expect(try MilestoneNotificationPlan(milestones: [milestone(reminder: nil)], profiles: [], now: date("2026-09-18")).reminders.isEmpty)
        let oldJSON = #"{"id":"5E6D5D49-548B-4486-81CF-40E643E0558F","title":"旧","kind":"countdown","targetDate":"2026-09-25","repeatsAnnually":false,"note":"","createdAt":0,"updatedAt":0}"#
        let decoded = try JSONDecoder().decode(Milestone.self, from: Data(oldJSON.utf8))
        #expect(decoded.reminder == nil)
    }

    @Test func rangeValidationRejectsAllInvalidReminderValuesWithoutCrashing() throws {
        for value in [DateReminder(daysBefore: -1), DateReminder(daysBefore: 366), DateReminder(hour: -1), DateReminder(hour: 24), DateReminder(minute: -1), DateReminder(minute: 60)] {
            #expect(throws: (any Error).self) { try value.validate() }
        }
        #expect(throws: DateReminderError.daysBeforeOutOfRange) { try DateReminder(daysBefore: 366).validate() }
        #expect(throws: DateReminderError.hourOutOfRange) { try DateReminder(hour: 24).validate() }
        #expect(throws: DateReminderError.minuteOutOfRange) { try DateReminder(minute: 60).validate() }
        #expect(throws: DateReminderError.daysBeforeOutOfRange) { try Milestone(title: "坏设置", targetDate: "2026-09-25", reminder: DateReminder(daysBefore: -1)).validate() }
        var value = profile(); value.birthdayReminder = DateReminder(minute: 99)
        #expect(throws: DateReminderError.minuteOutOfRange) { try value.validate() }
        #expect(throws: MilestoneNotificationPlanError.invalidWindowDays) { try MilestoneNotificationPlan(milestones: [], profiles: [], now: date("2026-09-18"), windowDays: 0) }
    }

    @Test func planUsesBeijingNaturalDaysAndNeverSchedulesPastFireTimes() throws {
        let before = try MilestoneNotificationPlan(milestones: [milestone(reminder: DateReminder(daysBefore: 1, hour: 9))], profiles: [], now: ISO8601DateFormatter().date(from: "2026-09-18T00:30:00Z")!)
        #expect(before.reminders.first?.fireDate == ISO8601DateFormatter().date(from: "2026-09-24T01:00:00Z"))
        let after = try MilestoneNotificationPlan(milestones: [milestone(reminder: DateReminder(daysBefore: 1, hour: 9))], profiles: [], now: ISO8601DateFormatter().date(from: "2026-09-24T02:00:00Z")!)
        #expect(after.reminders.isEmpty)
        let utcLate = try MilestoneNotificationPlan(milestones: [milestone(reminder: DateReminder(daysBefore: 0, hour: 9))], profiles: [], now: ISO8601DateFormatter().date(from: "2026-09-17T23:30:00Z")!)
        #expect(utcLate.reminders.first?.fireDate == ISO8601DateFormatter().date(from: "2026-09-25T01:00:00Z"))
    }

    @Test func thirtyDayWindowIncludesTargetBeyondWindowWhenLeadTimeReachesIt() throws {
        let item = milestone(target: "2027-09-20", repeat: true, reminder: DateReminder(daysBefore: 365, hour: 9))
        let plan = try MilestoneNotificationPlan(milestones: [item], profiles: [], now: date("2026-09-18"))
        #expect(plan.reminders.count == 1)
        #expect(plan.reminders[0].targetDate == "2027-09-20")
        #expect(plan.reminders[0].fireDate == ISO8601DateFormatter().date(from: "2026-09-20T01:00:00Z"))
        #expect(plan.windowEnd == ISO8601DateFormatter().date(from: "2026-10-17T16:00:00Z"))
    }

    @Test func annualReminderAtBoundaryChecksNextYearAfterTodaysFirePassed() throws {
        let item = milestone(target: "2020-09-18", repeat: true, reminder: DateReminder(daysBefore: 365, hour: 9))
        let now = ISO8601DateFormatter().date(from: "2026-09-17T02:00:00Z")!
        let plan = try MilestoneNotificationPlan(milestones: [item], profiles: [], now: now)
        #expect(plan.reminders.count == 1)
        #expect(plan.reminders[0].targetDate == "2027-09-18")
        #expect(plan.reminders[0].fireDate > now && plan.reminders[0].fireDate < plan.windowEnd)
    }

    @Test func birthdayReminderHonorsTrackingAndLunarRules() throws {
        let disabled = try MilestoneNotificationPlan(milestones: [], profiles: [profile(tracking: nil)], now: date("2026-09-18"))
        #expect(disabled.sources.isEmpty && disabled.reminders.isEmpty)
        let solar = try MilestoneNotificationPlan(milestones: [], profiles: [profile()], now: date("2026-09-18"))
        #expect(solar.reminders.count == 1 && solar.reminders[0].targetDate == "2026-09-25")
        var lunarProfile = profile(tracking: .lunar, reminder: DateReminder(daysBefore: 2, hour: 10, minute: 30))
        lunarProfile.birthYear = 2000; lunarProfile.birthMonth = 2; lunarProfile.birthDay = 5
        let lunar = try MilestoneNotificationPlan(milestones: [], profiles: [lunarProfile], now: date("2026-02-01"))
        #expect(lunar.reminders.count == 1 && lunar.reminders[0].targetDate == "2026-02-17")
        #expect(lunar.reminders[0].fireDate == ISO8601DateFormatter().date(from: "2026-02-15T02:30:00Z"))
    }

    @Test func sourceSnapshotChangesWhenTargetOrReminderChangesAndStaleRequestFails() throws {
        let item = milestone()
        let snapshot = try MilestoneNotificationPlan.snapshot(for: item)
        var changed = item; changed.reminder = DateReminder(daysBefore: 2)
        let changedSnapshot = try MilestoneNotificationPlan.snapshot(for: changed)
        #expect(snapshot.sourceKey == changedSnapshot.sourceKey && snapshot.version != changedSnapshot.version)
        let request = try #require(MilestoneNotificationPlan(milestones: [item], profiles: [], now: date("2026-09-18")).reminders.first)
        #expect(MilestoneNotificationPlan.isValid(request, milestones: [item], profiles: []))
        #expect(!MilestoneNotificationPlan.isValid(request, milestones: [changed], profiles: []))
        var removed = item; removed.reminder = nil
        #expect(!MilestoneNotificationPlan.isValid(request, milestones: [removed], profiles: []))
        #expect(try MilestoneNotificationPlan.snapshot(for: removed).sourceKey.hasPrefix("milestone:"))
        #expect(try MilestoneNotificationPlan.snapshot(for: profile(tracking: nil, reminder: nil)) == nil)
    }

    @Test func analysisRevisionExcludesBothBirthdayPreferencesButNotBirthFacts() throws {
        var original = profile(tracking: nil, reminder: nil)
        let base = try original.analysisRevision()
        original.birthdayTracking = .solar; original.birthdayReminder = DateReminder(daysBefore: 3)
        #expect(try original.analysisRevision() == base)
        var changed = original; changed.birthMinute += 1
        #expect(try changed.analysisRevision() != base)
        #expect(try AutomationSnapshot.revision(changed) != AutomationSnapshot.revision(original))
    }

    @Test func duplicateIDsAndInvalidNowAreRejected() throws {
        let same = milestone()
        var sameProfile = profile(); sameProfile.id = same.id
        #expect(throws: MilestoneNotificationPlanError.duplicateSourceIDs) { try MilestoneNotificationPlan(milestones: [same], profiles: [sameProfile], now: date("2026-09-18")) }
        #expect(throws: MilestoneNotificationPlanError.invalidNow) { try MilestoneNotificationPlan(milestones: [], profiles: [], now: Date(timeIntervalSinceReferenceDate: .nan)) }
    }
}
