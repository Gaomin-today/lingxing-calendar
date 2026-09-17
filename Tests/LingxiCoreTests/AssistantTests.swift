import Foundation
import Testing
@testable import LingxiCore

struct AssistantTests {
    private let parser = NaturalLanguageParser()
    // Thursday, 17 September 2026, 10:00 in Shanghai.
    private var now: Date { date("2026-09-17T10:00:00+08:00") }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    private func event(_ input: String, now: Date? = nil, file: StaticString = #filePath, line: UInt = #line) throws -> ParsedEvent {
        let result = parser.parse(input, now: now ?? self.now)
        guard case .event(let event) = result else {
            Issue.record("Expected event, got \(result)")
            throw NSError(domain: "AssistantTests", code: 1)
        }
        return event
    }

    private func assertClarification(_ input: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .needsClarification(let question) = parser.parse(input, now: now) else {
            Issue.record("Expected clarification for: \(input)")
            return
        }
        #expect(!(question.isEmpty))
    }

    @Test
    func testTomorrowMeetingAndDefaults() throws {
        let parsed = try event("提醒我明天下午三点开会")
        #expect(parsed.title == "开会")
        #expect(parsed.start == date("2026-09-18T15:00:00+08:00"))
        #expect(parsed.durationMinutes == 60)
        #expect(parsed.reminderMinutes == 10)
        #expect(parsed.repeatRule == "none")
    }

    @Test
    func testChineseHalfAndMinutes() throws {
        #expect(try event("后天上午十点半面试").start == date("2026-09-19T10:30:00+08:00"))
        #expect(try event("明天下午三点十五分开会").start == date("2026-09-18T15:15:00+08:00"))
        #expect(try event("今天晚上八点三刻读书").start == date("2026-09-17T20:45:00+08:00"))
    }

    @Test
    func testExplicit24HourTimes() throws {
        #expect(try event("2026-09-18 15:45 项目例会").start == date("2026-09-18T15:45:00+08:00"))
        #expect(try event("明天十五点二十分开会").start == date("2026-09-18T15:20:00+08:00"))
        #expect(try event("明天 03:00 出发").start == date("2026-09-18T03:00:00+08:00"))
        #expect(try event("2026/09/18 00:00 值班").start == date("2026-09-18T00:00:00+08:00"))
    }

    @Test
    func testMonthDayAndExplicitYear() throws {
        #expect(try event("9月20日下午两点签约").start == date("2026-09-20T14:00:00+08:00"))
        #expect(try event("九月二十日下午两点签约").start == date("2026-09-20T14:00:00+08:00"))
        #expect(try event("2027年1月2日上午九点面试").start == date("2027-01-02T09:00:00+08:00"))
        #expect(try event("明年1月2日 09:00 面试").start == date("2027-01-02T09:00:00+08:00"))
    }

    @Test
    func testNextWeekUsesMondayWeekStart() throws {
        #expect(try event("下周一上午九点开会").start == date("2026-09-21T09:00:00+08:00"))
        #expect(try event("下周日晚上八点读书").start == date("2026-09-27T20:00:00+08:00"))
        #expect(try event("这周五下午三点面试").start == date("2026-09-18T15:00:00+08:00"))
        #expect(try event("星期六中午十二点聚餐").start == date("2026-09-19T12:00:00+08:00"))
        #expect(try event("下周一 09:00 开会", now: date("2026-09-20T10:00:00+08:00")).start == date("2026-09-21T09:00:00+08:00"))
    }

    @Test
    func testDailyRecurrenceChoosesNextOccurrence() throws {
        let futureToday = try event("每天提醒我下午三点喝水")
        #expect(futureToday.repeatRule == "daily")
        #expect(futureToday.title == "喝水")
        #expect(futureToday.start == date("2026-09-17T15:00:00+08:00"))
        let passedToday = try event("每天上午九点复盘")
        #expect(passedToday.start == date("2026-09-18T09:00:00+08:00"))
    }

    @Test
    func testWeeklyRecurrenceChoosesNextOccurrence() throws {
        let parsed = try event("每周三下午三点开会")
        #expect(parsed.repeatRule == "weekly")
        #expect(parsed.start == date("2026-09-23T15:00:00+08:00"))
        #expect(parsed.title == "开会")
        #expect(try event("每周四上午九点开会").start == date("2026-09-24T09:00:00+08:00"))
        #expect(try event("每周四下午三点开会").start == date("2026-09-17T15:00:00+08:00"))
    }

    @Test
    func testDurationAndReminderAreNotStartTime() throws {
        let parsed = try event("提醒我明天下午三点开会，持续一个小时，提前三十分钟提醒")
        #expect(parsed.title == "开会")
        #expect(parsed.durationMinutes == 60)
        #expect(parsed.reminderMinutes == 30)
        #expect(try event("明天 15:00 开会，持续半小时").durationMinutes == 30)
        #expect(try event("明天 15:00 开会，提前两小时提醒").reminderMinutes == 120)
        #expect(try event("明天 15:00 开会，不用提醒").reminderMinutes == -1)
    }

    @Test
    func testMissingDateTimeAndTitleNeedClarification() {
        ["提醒我开会", "提醒我明天开会", "提醒我下午三点开会", "提醒我明天下午三点", "每周下午三点开会"].forEach { assertClarification($0) }
    }

    @Test
    func testAmbiguousTimeNeedsClarification() {
        ["明天三点开会", "明天晚上十二点出发", "明天上午十二点开会", "明天下午零点开会"].forEach { assertClarification($0) }
    }

    @Test
    func testInvalidCalendarAndClockValuesNeedClarification() {
        ["2026-02-29 15:00 开会", "2026-13-01 15:00 开会", "2026-04-31 15:00 开会", "明天25:00开会", "明天15:61开会", "明天下午三点，持续零分钟开会"].forEach { assertClarification($0) }
    }

    @Test
    func testPastDateIsNotSilentlyShifted() {
        ["今天上午九点开会", "周三下午三点开会", "9月1日下午三点开会", "2025-10-01 15:00 开会", "今天10:00开会", "每天今天上午九点开会"].forEach { assertClarification($0) }
    }

    @Test
    func testDateRolloverAndLeapYear() throws {
        #expect(try event("明天 15:00 开会", now: date("2026-12-31T10:00:00+08:00")).start == date("2027-01-01T15:00:00+08:00"))
        #expect(try event("2028-02-29 15:00 开会").start == date("2028-02-29T15:00:00+08:00"))
        #expect(try event("明天 15:00 开会", now: date("2026-09-17T18:00:00Z")).start == date("2026-09-19T15:00:00+08:00"))
    }

    @Test
    func testQuestionsAndChatNeverCreateEvents() {
        ["", "你好", "明天运势如何", "明天下午三点适合签约吗", "明天有几个日程", "帮我算卦", "明天开会会不会顺利", "我想聊聊面试", "帮我取消明天下午三点开会", "把明天下午三点会议改到五点", "明天下午三点有空吗"].forEach {
            #expect(parser.parse($0, now: now) == .notAnEvent)
        }
    }

    @Test
    func testMultipleDatesTimesAndRecurrenceNeedClarification() {
        ["明天后天下午三点开会", "明天下午三点开会五点吃饭", "明天下午三点到五点开会", "每天每周三下午三点开会", "明天15:00开会，提前10分钟和提前30分钟提醒"].forEach { assertClarification($0) }
    }

    @Test
    func testLunarAndForeignTimeZonesNeedClarification() {
        assertClarification("提醒我农历八月十五下午三点聚餐")
        assertClarification("提醒我明天纽约下午三点开会")
    }

    @Test
    func testMalformedOrUnsupportedTimesAreNotPartiallyAccepted() {
        ["下下周三下午三点开会", "过两天下午三点开会", "明天 15:001 开会", "明天 1000:00 开会", "明天15:00开会，持续1.5小时", "明天15:00开会，持续9223372036854775807小时", "明天15:00开会，提前9223372036854775807小时提醒"].forEach { assertClarification($0) }
    }

    @Test
    func testAdviceSeparatesFactTraditionAndAction() {
        let engine = AdviceEngine()
        let interview = engine.advice(for: "产品经理面试", on: now)
        #expect(interview.fact.contains("2026年9月17日"))
        #expect(interview.tradition.contains("不代表面试结果"))
        #expect(interview.action.contains("项目案例"))
        #expect(engine.advice(for: "去机场", on: now).action.contains("证件"))
        #expect(engine.advice(for: "签约", on: now).action.contains("退出条件"))
        #expect(engine.advice(for: "周会会议", on: now).action.contains("负责人"))
        #expect(engine.advice(for: "整理书架", on: now).tradition.contains("不生成没有来源的宜忌"))
    }

    @Test
    func testOfflineReplyDisclosesLimitsAndUsesSuppliedEvents() {
        let engine = AdviceEngine()
        #expect(engine.reply(to: "帮我算卦", on: now, eventTitles: []).contains("没有进行卦象计算"))
        #expect(engine.reply(to: "今天有哪些安排", on: now, eventTitles: ["项目例会", "面试"]).contains("项目例会、面试"))
        #expect(engine.reply(to: "神诞是什么", on: now, eventTitles: []).contains("核验来源"))
        #expect(engine.reply(to: "修改日程", on: now, eventTitles: []).contains("暂时不会自动修改"))
    }
}
