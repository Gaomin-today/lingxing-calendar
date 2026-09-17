import Foundation
import LingxiCore

struct AutomationRouteError: Error {
    let code: String
    let message: String
    var details: JSONValue? = nil
}

/// All requests enter the same main-actor stores used by the GUI. The CLI never
/// owns a second copy of the application's records or EventKit write state.
@MainActor final class AppAutomationRouter {
    private let store: AppStore
    private var journal: AutomationMutationJournal?
    private var journalError: String?
    let knowledge: KnowledgeLibrary
    private var queriedEvents: [UUID: CalendarEvent] = [:]
    init(store: AppStore) {
        self.store = store
        knowledge = KnowledgeLibrary.shared
        let url = store.repository.fileURL.deletingLastPathComponent()
            .appendingPathComponent(store.isPreviewMode ? "preview-mutations.json" : "automation-mutations.json")
        do { journal = try AutomationMutationJournal(fileURL: url) }
        catch { journalError = error.localizedDescription }
    }

    func handle(_ request: AutomationRequest) async -> AutomationResponse {
        do {
            guard request.version == 1 else { throw problem("unsupported_version", "只支持协议 version 1。") }
            guard store.automationEnabled else { throw problem("access_disabled", "本机 CLI 访问已关闭。") }
            guard let params = request.params.objectValue else { throw problem("invalid_params", "params 必须是 JSON 对象。") }
            if Self.mutations.contains(request.method) { return try mutate(request, params: params) }
            return .success(request: request, result: try await read(request.method, params))
        } catch let error as AutomationRouteError {
            return .failure(request: request, code: error.code, message: error.message, details: error.details)
        } catch let error as AutomationMutationJournalError {
            return .failure(request: request, code: error == .requestIDConflict ? "request_id_conflict" : "receipt_error", message: error.localizedDescription)
        } catch {
            return .failure(request: request, code: "invalid_request", message: error.localizedDescription)
        }
    }

    private func read(_ method: String, _ p: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "status":
            return .object([
                "version": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"),
                "protocolVersion": .number(1), "preview": .bool(store.isPreviewMode),
                "now": try .from(Date()), "today": .string(DateText.format(Date(), "yyyy-MM-dd")),
                "writesAvailable": .bool(journal != nil), "receiptError": optional(journalError),
                "activeProfileID": optional(store.birthProfiles.activeID?.uuidString),
                "notificationStatus": .string(store.notificationStatus),
                "appleCalendarAccess": .bool(store.system.canReadEvents), "appleRemindersAccess": .bool(store.system.canReadReminders),
                "timeZone": .string(store.calendar.gregorian.timeZone.identifier),
                "localStorageError": optional(store.storageError), "profileStorageError": optional(store.birthProfiles.error),
                "notesStorageError": optional(store.dayNotes.error)
            ])
        case "capabilities": return capabilities
        case "strength.show":
            let person = try profile(p)
            return .object(["profile": try profileEnvelope(person), "report": try .from(store.nativeStrength(for: person)), "strengthBasis": try strengthBasis(person)])
        case "hexagrams.show":
            let person = try profile(p)
            let clock = try referenceClock(p, person: person)
            do {
                return .object(["profile": try profileEnvelope(person), "hexagrams": try .from(store.personalHexagrams(for: person, at: clock.instant).get())])
            } catch { throw problem("hexagrams_unavailable", error.localizedDescription) }
        case "profiles.list":
            try ensureReadable("profiles")
            return .object(["profiles": .array(try store.birthProfiles.profiles.map(profileEnvelope)), "activeProfileID": optional(store.birthProfiles.activeID?.uuidString)])
        case "profiles.show": return try profileEnvelope(profile(p))
        case "chart.show":
            let person = try profile(p)
            return .object(["profile": try profileEnvelope(person), "charts": .array(try FourPillarsEngine().natalCharts(for: person).map(AutomationFacts.chart))])
        case "luck.show":
            let person = try profile(p)
            guard let gender = person.luckGender else { throw problem("missing_birth_data", "档案尚未填写排运所用性别。") }
            let engine = LuckCycleEngine()
            let chart = try engine.calculate(for: person, gender: gender)
            var result: [String: JSONValue] = ["profileID": .string(person.id.uuidString), "luck": AutomationFacts.luck(chart)]
            if let year = try integer(p, "year") {
                let flow = try engine.flowYear(year)
                result["flowYear"] = AutomationFacts.flowYear(flow, months: try engine.flowMonths(in: flow))
            }
            return .object(result)
        case "calendar.day", "context.day": return try await dayContext(p, includeEvents: method == "context.day")
        case "events.list":
            let from = try civilDate(required(p, "from"))
            let to = try civilDate(required(p, "to"))
            guard from < to, to.timeIntervalSince(from) <= 366 * 86400 else { throw problem("invalid_range", "from 含起点、to 不含终点，查询范围需在 1–366 天内。") }
            return try await eventList(from: from, to: to)
        case "events.show", "tasks.show":
            try ensureReadable("events")
            let id = try identifier(required(p, "id"))
            guard let event = store.allEvents.first(where: { $0.id == id }) ?? queriedEvents[id] else { throw problem("not_found", "未找到事项，请先查询日期范围或待办列表。") }
            guard method != "tasks.show" || event.isTask else { throw problem("wrong_kind", "该事项不是待办。") }
            return try eventEnvelope(event)
        case "tasks.list":
            try ensureReadable("events")
            let external = try await store.system.fetchReminders(calendarIDs: store.selectedReminderIDs)
            let items = store.events.filter(\.isTask) + external
            for item in external { queriedEvents[item.id] = item }
            return .object(["tasks": .array(try items.prefix(1000).map(eventEnvelope)), "truncated": .bool(items.count > 1000), "includesCompletedAndUndated": .bool(true)])
        case "journal.list", "insights.list":
            try ensureReadable("notes")
            let kind: DayNoteKind = method == "journal.list" ? .journal : .insight
            if let date = p["date"] { _ = try civilDate(try string(date, "date")) }
            let pid = try optionalProfileID(p)
            let items = store.dayNotes.notes.filter { $0.kind == kind && (p["date"] == nil || $0.date == p["date"]?.stringValue) && (pid == nil || $0.profileID == pid) }.sorted { $0.updatedAt > $1.updatedAt }
            let offset = max(0, try integer(p, "offset") ?? 0)
            let limit = min(100, max(1, try integer(p, "limit") ?? 20))
            return .object(["total": .number(Double(items.count)), "offset": .number(Double(offset)), "notes": .array(try items.dropFirst(offset).prefix(limit).map { try noteEnvelope($0, includeBody: false) })])
        case "journal.show", "insights.show":
            let note = try note(p)
            guard (method == "journal.show") == (note.kind == .journal) else { throw problem("wrong_kind", "请使用与内容类型对应的 show 命令。") }
            return try noteEnvelope(note)
        case "knowledge.search":
            if let query = p["query"], query.stringValue == nil { throw problem("invalid_field", "query 需要字符串。") }
            return try knowledge.search(query: p["query"]?.stringValue ?? "")
        case "knowledge.read": return try knowledge.read(id: required(p, "id"), offset: integer(p, "offset") ?? 0)
        case "open.day", "open.chart", "open.event", "open.journal":
            if method == "open.event" {
                let id = try identifier(required(p, "id"))
                guard let event = store.allEvents.first(where: { $0.id == id }) ?? queriedEvents[id] else { throw problem("not_found", "未找到事项；Apple 事项需先查询其日期范围。") }
                store.select(event.start); store.section = "月历"; store.editorEvent = event
            } else if method == "open.journal" {
                let item = try note(p); store.select(try civilDate(item.date)); store.highlightedNoteID = item.id
                if let pid = item.profileID, store.birthProfiles.profiles.contains(where: { $0.id == pid }) { store.birthProfiles.activeID = pid }
                store.section = "日笺"
            } else if method == "open.chart" {
                let item = try profile(p); store.birthProfiles.activeID = item.id; store.section = "四柱与八字"; store.baziPage = .natal
            } else { store.select(try civilDate(required(p, "date"))); store.section = "月历" }
            store.showMainAction?()
            return .object(["opened": .bool(true)])
        default: throw problem("unknown_method", "未知命令 \(method)。请先运行 capabilities。")
        }
    }

    private func referenceClock(_ p: [String: JSONValue], person: BirthProfile?) throws -> (text: String, date: Date, at: String, instant: Date) {
        let text = try required(p, "date"), date = try civilDate(text)
        let at = try p["at"].map { try string($0, "at") } ?? "12:00"
        let pieces = at.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2, pieces.allSatisfy({ $0.count == 2 && $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }),
              let hour = Int(pieces[0]), let minute = Int(pieces[1]), (0...23).contains(hour), (0...59).contains(minute) else { throw problem("invalid_time", "at 使用 00:00–23:59，默认为 12:00。") }
        let parts = store.calendar.gregorian.dateComponents([.year, .month, .day], from: date)
        let clock = BirthProfile(birthYear: parts.year!, birthMonth: parts.month!, birthDay: parts.day!, birthHour: hour, birthMinute: minute, birthTimeKnown: true,
                                 timeZoneIdentifier: store.calendar.gregorian.timeZone.identifier, dayBoundary: person?.dayBoundary ?? .midnight)
        let instant = try clock.resolvedBirthDate()!
        return (text, date, at, instant)
    }
    private func dayContext(_ p: [String: JSONValue], includeEvents: Bool) async throws -> JSONValue {
        let pid = try optionalProfileID(p)
        let person = try pid.map { id in try profile(["profile": .string(id.uuidString)]) }
        let (text, date, at, instant) = try referenceClock(p, person: person)
        let flow = try FourPillarsEngine().chart(at: instant, timeZone: store.calendar.gregorian.timeZone, dayBoundary: person?.dayBoundary ?? .midnight)
        var result: [String: JSONValue] = ["date": .string(text), "referenceTime": .string(at), "timeZone": .string(store.calendar.gregorian.timeZone.identifier), "flowChart": AutomationFacts.chart(flow),
            "almanac": AutomationFacts.almanac(try AlmanacEngine.shared.day(on: date)), "snapshotAt": try .from(Date())]
        result["festivals"] = .array(store.calendar.festivals(on: date).map { festival in
            .object(["name": .string(festival.name), "summary": .string(festival.summary), "region": .string(festival.region), "sourceTitle": .string(festival.sourceTitle), "sourceURL": .string(festival.sourceURL)])
        })
        if let person {
            let charts = try FourPillarsEngine().natalCharts(for: person)
            result["profile"] = try profileEnvelope(person)
            result["strengthBasis"] = try strengthBasis(person)
            result["nativeStrength"] = try .from(store.nativeStrength(for: person))
            switch store.personalHexagrams(for: person, at: instant) {
            case .success(let hexagrams): result["hexagrams"] = try .from(hexagrams)
            case .failure(let error): result["hexagrams"] = .null; result["hexagramsUnavailable"] = .string(error.localizedDescription)
            }
            result["natalCharts"] = .array(charts.map(AutomationFacts.chart))
            if charts.count == 1 {
                result["personalReading"] = AutomationFacts.reading(try PersonalDailyReadingEngine().analyze(natal: charts[0], flow: flow, strength: store.strength(for: person)))
            } else { result["personalReading"] = .null; result["uncertainty"] = .string("出生时刻不详，存在多个可能命盘。") }
            if let gender = person.luckGender, person.birthTimeKnown {
                let luck = try LuckCycleEngine().calculate(for: person, gender: gender)
                result["luck"] = AutomationFacts.luck(luck)
                result["activeCycleIndex"] = luck.activeCycle(at: instant).map { .number(Double($0.index)) } ?? .null
            }
        }
        if includeEvents {
            try ensureReadable("notes")
            result["events"] = try await eventList(from: date, to: store.calendar.gregorian.date(byAdding: .day, value: 1, to: date)!)
            result["notes"] = .array(try store.dayNotes.entries(on: text, profileID: pid).map { try noteEnvelope($0, includeBody: false) })
        }
        return .object(result)
    }

    private func eventList(from: Date, to: Date) async throws -> JSONValue {
        try ensureReadable("events")
        store.system.refreshAuthorization()
        let external = store.system.fetchEvents(from: from, to: to, calendarIDs: store.selectedCalendarIDs)
        let reminders = try await store.system.fetchReminders(calendarIDs: store.selectedReminderIDs)
        let records = store.events + external + reminders
        queriedEvents = Dictionary((external + reminders).prefix(2000).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let occurrences = store.scheduler.occurrences(of: records, from: from, to: to)
        let rows = try occurrences.prefix(2000).map { item in
            JSONValue.object(["occurrenceID": .string(item.id), "start": try .from(item.start), "end": try .from(item.end), "record": try eventEnvelope(item.event)])
        }
        return .object(["from": try .from(from), "toExclusive": try .from(to), "occurrences": .array(rows), "truncated": .bool(occurrences.count > 2000),
            "appleCalendarAccess": .bool(store.system.canReadEvents), "appleRemindersAccess": .bool(store.system.canReadReminders),
            "appleSourceScope": .string("仅用户在应用里选择的来源；CLI 本版只写本地记录。"), "appleError": optional(store.system.lastError)])
    }

    private func mutate(_ request: AutomationRequest, params p: [String: JSONValue]) throws -> AutomationResponse {
        guard let requestID = request.requestID, !requestID.isEmpty else { throw problem("request_id_required", "写入需 --request-id；重试时使用同一个 ID 和相同参数。") }
        guard journal != nil else { throw problem("writes_unavailable", "写入凭据不可用，已保护现有数据：\(journalError ?? "unknown")") }
        let fingerprint = try AutomationSnapshot.revision(JSONValue.object(["method": .string(request.method), "params": request.params]))
        var plan: AutomationMutationPlan
        if let old = try journal!.record(requestID: requestID, fingerprint: fingerprint) {
            if old.state == .completed { return .success(request: request, result: old.result!, replayed: true) }
            plan = old
        } else {
            plan = try makePlan(request, p, fingerprint: fingerprint)
            plan = try journal!.prepare(plan)
        }
        let current = try currentValue(entity: plan.entity, id: plan.entityID)
        let currentRevision = try current.map(AutomationSnapshot.revision)
        // A prepared mutation can have reached the domain file before a crash.
        // Reuse its exact desired UUID/content and never overwrite intervening edits.
        if currentRevision != plan.desiredRevision {
            guard currentRevision == plan.expectedRevision else { throw problem("revision_conflict", "记录已被修改，请重新读取；不会覆盖新内容。", .object(["currentRevision": optional(currentRevision), "id": .string(plan.entityID.uuidString)])) }
            try apply(plan)
        }
        guard try currentValue(entity: plan.entity, id: plan.entityID).map(AutomationSnapshot.revision) == plan.desiredRevision else {
            throw problem("write_verification_failed", "写入后的数据与计划不一致，已保留凭据；请重新读取记录核对。")
        }
        let result = try mutationResult(plan)
        do { try journal!.complete(requestID: requestID, fingerprint: fingerprint, result: result) }
        catch { throw problem("receipt_pending", "数据已写入，完成凭据尚未保存；请用相同 request-id 重试核对。", result) }
        return .success(request: request, result: result)
    }

    private func makePlan(_ request: AutomationRequest, _ p: [String: JSONValue], fingerprint: String) throws -> AutomationMutationPlan {
        let entity = request.method.hasPrefix("profiles.") ? "profiles" : (request.method.hasPrefix("events.") || request.method == "tasks.complete" ? "events" : "notes")
        let create = request.method.hasSuffix(".create") || (request.method == "insights.save" && p["id"] == nil)
        if request.method.hasSuffix(".delete") || request.method == "tasks.complete" {
            try checkFields(p, allowed: ["id", "revision"])
        } else if create {
            // New records receive an application-owned ID and have no previous
            // revision. Silently ignoring these fields would mislead the caller.
            try checkFields(p, allowed: Set(p.keys).subtracting(["id", "revision"]))
        }
        let id = create ? UUID() : try identifier(required(p, "id"))
        let old = try currentValue(entity: entity, id: id)
        if !create && old == nil { throw problem("not_found", "没有找到此本地记录。") }
        let expected = try old.map(AutomationSnapshot.revision)
        if !create, try required(p, "revision") != expected { throw problem("revision_conflict", "记录版本已变化，请重新读取。", .object(["currentRevision": optional(expected)])) }
        let desired: JSONValue?
        if request.method.hasSuffix(".delete") {
            if entity == "notes", let old { try checkNoteKind(decode(DayNote.self, old), method: request.method) }
            desired = nil
        } else if entity == "profiles" {
            var value: BirthProfile
            if let old { value = try decode(BirthProfile.self, old) }
            else {
                for key in ["name", "birthYear", "birthMonth", "birthDay", "birthTimeKnown", "timeZoneIdentifier"] { guard p[key] != nil else { throw problem("missing_field", "缺少 \(key)。") } }
                value = BirthProfile(id: id)
            }
            let allowed = Set(["name", "birthYear", "birthMonth", "birthDay", "birthHour", "birthMinute", "birthTimeKnown", "timeZoneIdentifier", "birthplace", "dayBoundary", "luckGender", "strengthAssumption"])
            value = try patched(value, params: p, allowed: allowed)
            let previouslyKnown = old?["birthTimeKnown"]?.boolValue ?? false
            if !previouslyKnown && value.birthTimeKnown && (p["birthHour"] == nil || p["birthMinute"] == nil) { throw problem("missing_field", "从未知改为已知出生时刻，需要显式 birthHour 与 birthMinute。") }
            value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            value.birthplace = value.birthplace.trimmingCharacters(in: .whitespacesAndNewlines)
            value.timeZoneIdentifier = value.timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard BirthProfileStore.nameError(for: value.name) == nil else { throw problem("invalid_profile", "档案名称需要 1–40 个字符。") }
            try value.validate(); desired = try .from(value)
        } else if entity == "events" {
            if let raw = p["destination"], raw.stringValue != "local" { throw problem("unsupported_destination", "destination 只接受字符串 local。本版 CLI 只写本地记录。") }
            var value: CalendarEvent
            if let old { value = try decode(CalendarEvent.self, old) }
            else {
                let start = try timestamp(required(p, "start"))
                let end = try p["end"].map { try timestamp(string($0, "end")) }
                value = CalendarEvent(id: id, title: try required(p, "title"), start: start, end: end ?? start.addingTimeInterval(3600), reminderMinutes: nil)
            }
            if request.method == "tasks.complete" {
                guard value.isTask else { throw problem("wrong_kind", "该记录不是待办。") }
                value.isCompleted = true
            } else {
                let allowed = Set(["title", "start", "end", "notes", "isAllDay", "repeatRule", "reminderMinutes", "isTask", "isCompleted", "taskHasDueDate", "taskDueHasTime", "location"])
                value = try patched(value, params: p, allowed: allowed.union(["destination"]), ignored: ["destination"])
            }
            try validateEvent(value)
            desired = try .from(value)
        } else {
            var value: DayNote
            if let old { value = try decode(DayNote.self, old); try checkNoteKind(value, method: request.method) }
            else { value = DayNote(id: id, kind: request.method.hasPrefix("insights.") ? .insight : .journal, date: try required(p, "date"), title: try required(p, "title"), body: try required(p, "body"), source: .agent) }
            let allowed = Set(["date", "title", "body", "profileID", "author", "profileRevision", "strengthAssessment"])
            value = try patched(value, params: p, allowed: allowed)
            value.source = .agent; value.author = value.author ?? "CLI"; value.updatedAt = Date()
            if let pid = value.profileID {
                let person = try profile(["profile": .string(pid.uuidString)])
                let revision = try AutomationSnapshot.revision(person)
                if value.kind == .insight {
                    guard value.profileRevision == revision else { throw problem("profile_revision_conflict", "分析需基于当前档案；先读取 profiles show，再填写 profileRevision。") }
                }
            }
            try value.validate(); desired = try .from(value)
        }
        return AutomationMutationPlan(requestID: request.requestID!, fingerprint: fingerprint, method: request.method, entity: entity, entityID: id, expectedRevision: expected,
                                      desired: desired, desiredRevision: try desired.map(AutomationSnapshot.revision))
    }

    private func currentValue(entity: String, id: UUID) throws -> JSONValue? {
        try ensureReadable(entity)
        switch entity {
        case "events": return try store.events.first(where: { $0.id == id }).map(JSONValue.from)
        case "profiles": return try store.birthProfiles.profiles.first(where: { $0.id == id }).map(JSONValue.from)
        case "notes": return try store.dayNotes.notes.first(where: { $0.id == id }).map(JSONValue.from)
        default: throw problem("invalid_entity", "不支持该对象。")
        }
    }
    private func apply(_ plan: AutomationMutationPlan) throws {
        let success: Bool
        if let desired = plan.desired {
            switch plan.entity {
            case "events": success = store.save(try decode(CalendarEvent.self, desired), requestNotificationPermission: false)
            case "profiles": success = store.birthProfiles.save(try decode(BirthProfile.self, desired))
            default: success = store.dayNotes.save(try decode(DayNote.self, desired))
            }
        } else {
            switch plan.entity {
            case "events": success = store.events.first(where: { $0.id == plan.entityID }).map { store.delete($0, requestNotificationPermission: false) } ?? true
            case "profiles": success = store.birthProfiles.profiles.first(where: { $0.id == plan.entityID }).map { store.birthProfiles.delete($0) } ?? true
            default: success = store.dayNotes.notes.first(where: { $0.id == plan.entityID }).map { store.dayNotes.delete($0) } ?? true
            }
        }
        guard success else { throw problem("write_failed", store.dayNotes.error ?? store.birthProfiles.error ?? store.status ?? "未保存。") }
    }
    private func mutationResult(_ plan: AutomationMutationPlan) throws -> JSONValue {
        var value: [String: JSONValue] = ["id": .string(plan.entityID.uuidString), "entity": .string(plan.entity), "saved": .bool(true), "deleted": .bool(plan.desired == nil), "revision": optional(plan.desiredRevision)]
        if let desired = plan.desired { value["record"] = desired }
        if plan.entity == "events" {
            value["destination"] = .string("local")
            value["notification"] = .object(["state": .string(store.isPreviewMode ? "preview_suppressed" : "refresh_requested"), "currentStatus": .string(store.notificationStatus)])
        }
        return .object(value)
    }

    private func profile(_ p: [String: JSONValue]) throws -> BirthProfile {
        try ensureReadable("profiles")
        let id = try identifier(p["profile"]?.stringValue ?? p["profileID"]?.stringValue ?? required(p, "id"))
        guard let value = store.birthProfiles.profiles.first(where: { $0.id == id }) else { throw problem("not_found", "没有找到这个出生档案。") }
        return value
    }
    private func optionalProfileID(_ p: [String: JSONValue]) throws -> UUID? {
        guard let raw = p["profile"] ?? p["profileID"], raw != .null else { return nil }
        return try identifier(string(raw, "profile"))
    }
    private func note(_ p: [String: JSONValue]) throws -> DayNote {
        try ensureReadable("notes")
        let id = try identifier(required(p, "id"))
        guard let value = store.dayNotes.notes.first(where: { $0.id == id }) else { throw problem("not_found", "没有找到这篇日笺。") }; return value
    }
    private func profileEnvelope(_ profile: BirthProfile) throws -> JSONValue { .object(["profile": try .from(profile), "revision": .string(try AutomationSnapshot.revision(profile))]) }
    private func eventEnvelope(_ event: CalendarEvent) throws -> JSONValue { .object(["event": try .from(event), "revision": .string(try AutomationSnapshot.revision(event)), "cliWritable": .bool(!event.isExternal)]) }
    private func noteEnvelope(_ note: DayNote, includeBody: Bool = true) throws -> JSONValue {
        var value = try JSONValue.from(note).objectValue!
        if !includeBody { value.removeValue(forKey: "body") }
        return .object(["note": .object(value), "revision": .string(try AutomationSnapshot.revision(note)), "stale": .bool(store.dayNotes.isStale(note, profiles: store.birthProfiles.profiles))])
    }
    private func patched<T: Codable>(_ value: T, params: [String: JSONValue], allowed: Set<String>, ignored: Set<String> = []) throws -> T {
        let control = Set(["id", "revision"])
        try checkFields(params, allowed: allowed.union(control))
        var object = try JSONValue.from(value).objectValue!
        for (key, item) in params where allowed.contains(key) && !ignored.contains(key) { object[key] = item }
        return try decode(T.self, .object(object))
    }
    private func checkFields(_ params: [String: JSONValue], allowed: Set<String>) throws {
        let unknown = Set(params.keys).subtracting(allowed)
        guard unknown.isEmpty else { throw problem("unknown_field", "未知字段：\(unknown.sorted().joined(separator: ", "))") }
    }
    private func validateEvent(_ event: CalendarEvent) throws {
        guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, event.title.count <= 200, event.notes.count <= 100_000 else { throw problem("invalid_event", "标题需为 1–200 字，备注最多 100000 字。") }
        guard event.start.timeIntervalSince1970.isFinite, event.end.timeIntervalSince1970.isFinite,
              event.isTask ? event.end >= event.start : event.end > event.start else { throw problem("invalid_event", "结束时间必须晚于开始时间（待办允许相等）。") }
        guard event.reminderMinutes == nil || (0...10080).contains(event.reminderMinutes!) else { throw problem("invalid_reminder", "提醒提前量范围为 0–10080 分钟；null 表示不提醒。") }
        guard !event.isExternal else { throw problem("unsupported_destination", "CLI 本版只写本地记录。") }
    }
    private func checkNoteKind(_ note: DayNote, method: String) throws {
        guard method.hasPrefix("journal.") == (note.kind == .journal) else { throw problem("wrong_kind", "命令与日笺类型不一致。") }
    }
    private func civilDate(_ value: String) throws -> Date {
        let p = value.split(separator: "-", omittingEmptySubsequences: false)
        guard value.count == 10, p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
              p.allSatisfy({ $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }),
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), BirthProfile.supportedYears.contains(y) else { throw problem("invalid_date", "日期格式为 YYYY-MM-DD，支持 1901–2099。") }
        let profile = BirthProfile(birthYear: y, birthMonth: m, birthDay: d)
        let date = try profile.referenceBirthDate()
        return store.calendar.gregorian.startOfDay(for: date)
    }
    private func timestamp(_ value: String) throws -> Date { try decode(Date.self, .string(value)) }
    private func decode<T: Decodable>(_ type: T.Type, _ value: JSONValue) throws -> T { try AutomationJSON.decode(type, from: AutomationJSON.encode(value)) }
    private func required(_ p: [String: JSONValue], _ key: String) throws -> String { guard let value = p[key] else { throw problem("missing_field", "缺少 \(key)。") }; return try string(value, key) }
    private func string(_ value: JSONValue, _ name: String) throws -> String { guard let string = value.stringValue, !string.isEmpty else { throw problem("invalid_field", "\(name) 需要非空字符串。") }; return string }
    private func integer(_ p: [String: JSONValue], _ key: String) throws -> Int? { guard let value = p[key] else { return nil }; if let n = value.intValue { return n }; if let s = value.stringValue, let n = Int(s) { return n }; throw problem("invalid_field", "\(key) 需要整数。") }
    private func identifier(_ value: String) throws -> UUID { guard let id = UUID(uuidString: value) else { throw problem("invalid_id", "标识需要 UUID。") }; return id }
    private func optional(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
    private func problem(_ code: String, _ message: String, _ details: JSONValue? = nil) -> AutomationRouteError { AutomationRouteError(code: code, message: message, details: details) }

    private func ensureReadable(_ entity: String) throws {
        do {
            let unchanged: Bool
            switch entity {
            case "events":
                guard store.storageError == nil else { throw problem("storage_unavailable", store.storageError!) }
                unchanged = try store.repository.load() == store.events
            case "profiles":
                guard !store.birthProfiles.isReadOnly else { throw problem("storage_unavailable", store.birthProfiles.error ?? "档案不可读。") }
                unchanged = try store.birthProfiles.repository.load() == store.birthProfiles.profiles
            default:
                guard !store.dayNotes.isReadOnly else { throw problem("storage_unavailable", store.dayNotes.error ?? "日笺不可读。") }
                unchanged = try store.dayNotes.repository.load() == store.dayNotes.notes
            }
            guard unchanged else { throw problem("storage_changed", "磁盘文件在应用外发生了变化，请重启应用核对后再操作。") }
        } catch let error as AutomationRouteError { throw error }
        catch { throw problem("storage_unavailable", "原文件无法读取，已停止操作并保留：\(error.localizedDescription)") }
    }
    private func strengthBasis(_ person: BirthProfile) throws -> JSONValue {
        if let explicit = person.strengthAssumption, explicit != .unspecified {
            return .object(["source": .string("profile_override"), "assessment": .string(explicit.rawValue)])
        }
        try ensureReadable("notes")
        if let note = store.dayNotes.latestAssessment(for: person) {
            return .object(["source": .string("agent_insight"), "assessment": .string(note.strengthAssessment!.rawValue), "noteID": .string(note.id.uuidString), "author": optional(note.author), "profileRevision": optional(note.profileRevision)])
        }
        let report = store.nativeStrength(for: person)
        return .object(["source": .string("local_rule"), "assessment": .string(report.assessment.rawValue), "ruleVersion": .string(report.ruleVersion), "label": .string(report.label)])
    }

    static let mutations: Set<String> = ["profiles.create", "profiles.update", "profiles.delete", "events.create", "events.update", "events.delete", "tasks.complete", "journal.create", "journal.update", "journal.delete", "insights.save", "insights.delete"]
    private var capabilities: JSONValue {
        let reads = ["status", "capabilities", "profiles.list", "profiles.show", "chart.show", "luck.show", "strength.show", "hexagrams.show", "calendar.day", "context.day", "events.list", "events.show", "tasks.list", "tasks.show", "journal.list", "journal.show", "insights.list", "insights.show", "knowledge.search", "knowledge.read", "open.day", "open.chart", "open.event", "open.journal"]
        return .object(["protocolVersion": .number(1), "readMethods": .array(reads.map(JSONValue.string)), "writeMethods": .array(Self.mutations.sorted().map(JSONValue.string)),
            "writeContract": .string("写入必填 request_id；更新/删除必填 id 与 revision。相同请求重试使用同ID同参数。已完成的重放返回历史凭据，查询记录可确认当前状态。"),
            "dateContract": .string("date/from/to 为 YYYY-MM-DD（Asia/Shanghai）；start/end 为带时区的 ISO8601。from 含、to 不含。calendar/context 默认正午，可用 at=HH:mm。"),
            "eventCreate": .string("title,start必填；end默认一小时后，reminderMinutes默认null；可填end,notes,isTask,isAllDay,repeatRule(none/daily/weekly),reminderMinutes,taskHasDueDate,taskDueHasTime,location；destination只接受local。"),
            "profileCreate": .string("name,birthYear,birthMonth,birthDay,birthTimeKnown,timeZoneIdentifier必填；已知时刻还需birthHour,birthMinute；可填birthplace,dayBoundary(midnight/ziHour23),luckGender(male/female),strengthAssumption(unspecified/strong/weak)。"),
            "noteCreate": .string("journal create / insights save：date,title,body必填；可填profileID,author,profileRevision；insight关联档案需当前profileRevision，strengthAssessment为可选strong/weak/unspecified；来源固定agent。"),
            "profileSelector": .string("chart/luck/strength/hexagrams/context使用profile=UUID；profiles show可用id。读取不会改变当前UI档案。"),
            "personalAnalysis": .string("strength show返回本地普通扶抑初判、证据、规则版本；每日解读优先手动覆盖，其次有效Agent分析，再用本地初判。context包含nativeStrength与hexagrams。"),
            "hexagrams": .string("hexagrams show必填profile,date，可填at=HH:mm（北京时间参考，默认12:00）；返回先后天和立春年/节月/六日卦、有效时段及规则。卦的自然日按档案出生时区换日，缺时刻或性别不猜补。"),
            "knowledge": .string("search query可省略以列出条目；read id必填，offset按字符计；应用的外部Agent面板可添加本机技能文件夹。"),
            "notes": .string("list仅返回摘要，可按date/profile筛选并传offset/limit。show读取正文；insights save提供id+revision时更新。"),
            "restrictedWrites": .string("create不接受id/revision，由应用生成新ID；delete和tasks.complete仅接受id/revision；tasks.complete只完成已有待办。"),
            "appleWrites": .bool(false), "notificationContract": .string("保存成功和通知送达分别报告；CLI不触发系统授权弹窗。请在应用设置开启通知。")])
    }
}
