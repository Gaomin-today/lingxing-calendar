import Foundation
import Testing
import LingxiAgent
import LingxiCore
@testable import LingxiApp

struct AppAutomationToolProviderTests {
    private func dayCall(_ arguments: [String: JSONValue] = [:]) -> AgentToolCall {
        var values: [String: JSONValue] = ["date": .string("2026-09-28")]
        values.merge(arguments) { _, new in new }
        return AgentToolCall(id: "day-call", name: .dayContext, arguments: values)
    }

    private func cloudResult(_ call: AgentToolCall, payload: JSONValue) throws -> AgentToolResult {
        try AppAutomationToolProvider.result(for: call,
                                              request: AppAutomationToolProvider.request(for: call, cloudOnly: true),
                                              payload: payload, cloudOnly: true)
    }

    private func dayPayload(snapshotAt: String = "first-read", privateValue: String = "private-alpha") -> JSONValue {
        .object([
            "date": .string("2026-09-28"), "referenceTime": .string("12:00"),
            "timeZone": .string("Asia/Shanghai"),
            "flowChart": .object(["dayMaster": .string("甲"), "profile": .object(["name": .string(privateValue)]),
                                   "snapshotAt": .string(snapshotAt)]),
            "almanac": .object(["yi": .array([.string("会友")]), "luck": .string("传统分类")]),
            "festivals": .array([]), "snapshotAt": .string(snapshotAt),
            "profile": .object(["name": .string(privateValue)]), "notes": .array([.string(privateValue)]),
            "events": .array([.string(privateValue)]), "personalReading": .string(privateValue),
            "private": .string(privateValue), "unexpected": .string(privateValue)
        ])
    }

    private func occurrence(title: String = "合成事项", start: String = "2026-09-28T02:00:00.000Z",
                            privateValue: String = "private-alpha", revision: String = "private-revision-1") -> JSONValue {
        .object([
            "occurrenceID": .string("private-occurrence"), "start": .string(start),
            "end": .string("2026-09-28T03:00:00.000Z"), "snapshotAt": .string(privateValue),
            "record": .object([
                "revision": .string(revision), "cliWritable": .bool(false),
                "event": .object([
                    "id": .string("private-id"), "title": .string(title),
                    "start": .string("2000-01-01T00:00:00.000Z"), "end": .string("2000-01-01T01:00:00.000Z"),
                    "isAllDay": .bool(false), "isTask": .bool(false), "isCompleted": .bool(false),
                    "notes": .string(privateValue), "location": .string(privateValue),
                    "externalID": .string(privateValue), "externalCalendarID": .string(privateValue),
                    "externalCalendarTitle": .string(privateValue), "externalKind": .string("appleCalendar"),
                    "externalModifiedAt": .string(privateValue), "reminderMinutes": .number(30),
                    "profile": .object(["name": .string(privateValue)]), "unknown": .string(privateValue)
                ])
            ])
        ])
    }

    private func eventsPayload(_ rows: [JSONValue], error: JSONValue = .null,
                               snapshotAt: String = "first-read") -> JSONValue {
        .object([
            "from": .string("2026-09-27T16:00:00.000Z"), "toExclusive": .string("2026-09-28T16:00:00.000Z"),
            "occurrences": .array(rows), "truncated": .bool(false),
            "appleCalendarAccess": .bool(true), "appleRemindersAccess": .bool(false),
            "appleError": error, "snapshotAt": .string(snapshotAt),
            "notes": .array([.string("private-note")]), "profile": .string("private-profile")
        ])
    }

    @Test func cloudDayDropsProfileSelectorsAndUsesPureCalendarRoute() throws {
        let call = dayCall(["profile": .string("private-profile"), "profileID": .string("another-profile"),
                            "id": .string("private-id"), "includeEvents": .bool(true), "method": .string("context.day")])
        let request = try AppAutomationToolProvider.request(for: call, cloudOnly: true)
        #expect(request.method == "calendar.day")
        #expect(request.params == .object(["date": .string("2026-09-28"), "at": .string("12:00")]))
        let local = try AppAutomationToolProvider.request(for: call)
        #expect(local.method == "context.day")
        #expect(local.params["profile"] == .string("private-profile"))
    }

    @Test func cloudDayTimeMustBeCanonicalAndValid() throws {
        for invalid in ["1:00", "01:0", "24:00", "12:60", "12:00:00", " 12:00", "12:00\n", "１２:００"] {
            #expect(throws: AgentToolError.self) {
                try AppAutomationToolProvider.request(for: dayCall(["at": .string(invalid)]), cloudOnly: true)
            }
        }
        for invalid in [JSONValue.null, .number(12), .object(["profile": .string("private")])] {
            #expect(throws: AgentToolError.self) {
                try AppAutomationToolProvider.request(for: dayCall(["at": invalid]), cloudOnly: true)
            }
        }
        let request = try AppAutomationToolProvider.request(for: dayCall(["at": .string("23:59")]), cloudOnly: true)
        #expect(request.params["at"] == .string("23:59"))
    }

    @Test func cloudDateRejectsInvalidOrExpandedSelectors() throws {
        for invalid in ["2026-02-30", "2026-9-28", "2026-09-28T12:00:00Z", "1900-12-31", "2100-01-01", "2026-09-28\n"] {
            #expect(throws: AgentToolError.self) {
                try AppAutomationToolProvider.request(for: dayCall(["date": .string(invalid)]), cloudOnly: true)
            }
        }
        #expect(throws: AgentToolError.self) {
            try AppAutomationToolProvider.request(for: AgentToolCall(name: .eventsContext,
                arguments: ["from": .string("2026-01-01"), "to": .string("2026-12-31")]), cloudOnly: true)
        }
    }

    @Test func cloudEventsAlwaysUseOneDayAndIgnoreExtraArguments() throws {
        let call = AgentToolCall(name: .eventsContext, arguments: [
            "date": .string("2024-02-29"), "from": .string("1901-01-01"), "to": .string("2099-12-31"),
            "profile": .string("private"), "limit": .number(10_000), "includeNotes": .bool(true)
        ])
        let request = try AppAutomationToolProvider.request(for: call, cloudOnly: true)
        #expect(request.method == "events.list")
        #expect(request.params == .object(["from": .string("2024-02-29"), "to": .string("2024-03-01")]))
    }

    @Test func cloudToolSurfaceRejectsEveryPrivateTool() throws {
        #expect(AppAutomationToolProvider.allowedTools(cloudOnly: true) == Set([.dayContext, .eventsContext]))
        for name in AgentToolName.allCases where name != .dayContext && name != .eventsContext {
            #expect(throws: AgentToolError.self) {
                try AppAutomationToolProvider.request(for: AgentToolCall(name: name,
                    arguments: ["date": .string("2026-09-28")]), cloudOnly: true)
            }
        }
    }

    @Test func cloudDayOnlySharesCalendarFieldsAndPublicSemanticsControlRevision() throws {
        let first = try cloudResult(dayCall(), payload: dayPayload())
        let second = try cloudResult(dayCall(["at": .string("12:00"), "profile": .string("ignored")]),
                                     payload: dayPayload(snapshotAt: "second-read", privateValue: "private-beta"))
        let object = try #require(first.payload.objectValue)
        #expect(Set(object.keys) == Set(["date", "referenceTime", "timeZone", "flowChart", "almanac", "festivals"]))
        #expect(object["flowChart"] == .object(["dayMaster": .string("甲")]))
        #expect(object["almanac"]?["luck"] == .string("传统分类"))
        #expect(!String(decoding: try AutomationJSON.encode(first.payload), as: UTF8.self).contains("private-"))
        #expect(first.payload == second.payload)
        #expect(first.sourceRevision == second.sourceRevision)
        #expect(first.sourceRevision?.count == 64)
        #expect(first.sourceRef == second.sourceRef)
        #expect(first.sourceRef.hasPrefix("automation:calendar.day:"))
        var changed = try #require(dayPayload().objectValue)
        changed["almanac"] = .object(["yi": .array([.string("休息")])])
        #expect(try cloudResult(dayCall(), payload: .object(changed)).sourceRevision != first.sourceRevision)
    }

    @Test func cloudEventsRemovePrivateFieldsAndBindOccurrenceTimes() throws {
        let call = AgentToolCall(name: .eventsContext, arguments: ["date": .string("2026-09-28")])
        let first = try cloudResult(call, payload: eventsPayload([occurrence()]))
        let second = try cloudResult(call, payload: eventsPayload([
            occurrence(privateValue: "private-beta", revision: "private-revision-2")
        ], snapshotAt: "second-read"))
        let row = try #require(first.payload["occurrences"]?.arrayValue?.first?.objectValue)
        #expect(Set(row.keys) == Set(["title", "start", "end", "isAllDay", "isTask", "isCompleted", "source"]))
        #expect(row["start"] == .string("2026-09-28T02:00:00.000Z"))
        #expect(row["source"] == .string("appleCalendar"))
        #expect(!String(decoding: try AutomationJSON.encode(first.payload), as: UTF8.self).contains("private-"))
        #expect(first.payload == second.payload)
        #expect(first.sourceRevision == second.sourceRevision)
        #expect(first.sourceRevision?.count == 64)
        #expect(first.sourceRef.hasPrefix("automation:events.list:"))
        #expect(try cloudResult(call, payload: eventsPayload([occurrence(title: "改后的标题")])).sourceRevision != first.sourceRevision)
        #expect(try cloudResult(call, payload: eventsPayload([occurrence(start: "2026-09-28T01:00:00.000Z")])).sourceRevision != first.sourceRevision)
    }

    @Test func cloudEventSetOrderingDoesNotInventANewRevision() throws {
        let call = AgentToolCall(name: .eventsContext, arguments: ["date": .string("2026-09-28")])
        let a = occurrence(title: "事项甲")
        let b = occurrence(title: "事项乙")
        let first = try cloudResult(call, payload: eventsPayload([a, b]))
        let second = try cloudResult(call, payload: eventsPayload([b, a]))
        #expect(first.payload == second.payload)
        #expect(first.sourceRevision == second.sourceRevision)
        #expect(try cloudResult(call, payload: eventsPayload([a])).sourceRevision != first.sourceRevision)
    }

    @Test func emptyCloudEventCollectionHasAStableRevisionAndAvailabilityIsNotHidden() throws {
        let call = AgentToolCall(name: .eventsContext, arguments: ["date": .string("2026-09-28")])
        let first = try cloudResult(call, payload: eventsPayload([]))
        let second = try cloudResult(call, payload: eventsPayload([], snapshotAt: "later"))
        #expect(first.payload["occurrences"] == .array([]))
        #expect(first.sourceRevision?.count == 64)
        #expect(first.sourceRevision == second.sourceRevision)
        let failed = try cloudResult(call, payload: eventsPayload([], error: .string("private-account-path")))
        #expect(failed.payload["appleReadFailed"] == .bool(true))
        #expect(failed.sourceRevision != first.sourceRevision)
        #expect(!String(decoding: try AutomationJSON.encode(failed.payload), as: UTF8.self).contains("private-"))
    }

    @Test func cloudMalformedEventPayloadFailsInsteadOfPretendingItIsEmpty() throws {
        let call = AgentToolCall(name: .eventsContext, arguments: ["date": .string("2026-09-28")])
        #expect(throws: AgentToolError.self) { try cloudResult(call, payload: .object([:])) }
        #expect(throws: AgentToolError.self) { try cloudResult(call, payload: eventsPayload([.object([:])])) }
    }
}
