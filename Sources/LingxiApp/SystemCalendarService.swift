import AppKit
import Combine
import CryptoKit
import EventKit
import LingxiCore

struct SystemCalendarChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let sourceTitle: String
    let isReminder: Bool
    let isWritable: Bool
    let colorHex: UInt
}

/// Date-only reminders are civil dates, not midnight instants in the Mac's
/// current zone. Anchor their display to the app calendar (Beijing), while
/// timed reminders retain the provider's actual time-zone semantics.
enum SystemReminderDateCodec {
    static func date(from components: DateComponents) -> Date? {
        let timed = components.hour != nil || components.minute != nil
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timed ? (components.timeZone ?? .current) : CalendarEngine.timeZone
        var normalized = components
        normalized.calendar = calendar
        normalized.timeZone = calendar.timeZone
        return calendar.date(from: normalized)
    }

    static func components(for date: Date, hasTime: Bool, originalTimeZone: TimeZone?) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = hasTime ? (originalTimeZone ?? .current) : CalendarEngine.timeZone
        let parts: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute, .second] : [.year, .month, .day]
        var result = calendar.dateComponents(parts, from: date)
        result.calendar = calendar
        result.timeZone = hasTime ? calendar.timeZone : nil
        return result
    }
}

enum SystemCalendarError: LocalizedError {
    case permission(String), unavailable, missing, stale, readOnly(String), invalid(String)

    var errorDescription: String? {
        switch self {
        case .permission(let name): return "尚未获得\(name)完整访问权限，请在设置中连接。"
        case .unavailable: return "系统暂时无法读取提醒事项，请稍后刷新。"
        case .missing: return "这条记录已被删除或移动，请刷新后重新打开。"
        case .stale: return "这条记录已在其他应用中改变。为避免覆盖，请刷新后重新打开再编辑。"
        case .readOnly(let reason), .invalid(let reason): return reason
        }
    }
}

/// EventKit is the source of truth. Only value snapshots live here; no system
/// records are copied into EventRepository or reused across store changes.
@MainActor
final class SystemCalendarService: ObservableObject {
    @Published private(set) var calendars: [SystemCalendarChoice] = []
    @Published private(set) var eventPermission = "未连接"
    @Published private(set) var reminderPermission = "未连接"
    @Published private(set) var lastError: String?
    var onChange: (() -> Void)?

    private let store: EKEventStore
    private var observer: NSObjectProtocol?
    private struct Snapshot {
        let value: CalendarEvent
        let calendarItemID: String
    }
    // Keep the original editing baseline even if background refresh discovers
    // a newer version. Expired drafts are rejected rather than guessed at.
    private var snapshots: [String: Snapshot] = [:]
    // A creation receipt is deliberately separate from fetched snapshots.
    // Only this process's new saves can be rolled back as an entire series.
    private var createdReceipts: [UUID: Snapshot] = [:]

    init() {
        store = EKEventStore()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAuthorization()
                self?.onChange?()
            }
        }
        refreshAuthorization()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var canReadEvents: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var canReadReminders: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    func refreshAuthorization() {
        eventPermission = permissionLabel(EKEventStore.authorizationStatus(for: .event))
        reminderPermission = permissionLabel(EKEventStore.authorizationStatus(for: .reminder))
        var choices: [SystemCalendarChoice] = []
        if canReadEvents { choices += store.calendars(for: .event).map { choice($0, isReminder: false) } }
        if canReadReminders { choices += store.calendars(for: .reminder).map { choice($0, isReminder: true) } }
        calendars = choices.sorted {
            if $0.isReminder != $1.isReminder { return !$0.isReminder }
            return ($0.sourceTitle + $0.title).localizedStandardCompare($1.sourceTitle + $1.title) == .orderedAscending
        }
        if !canReadEvents && !canReadReminders { snapshots.removeAll() }
    }

    func requestEventsAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            lastError = granted ? nil : "日历访问未获允许；本地日历仍然可用。"
        } catch { lastError = error.localizedDescription }
        refreshAuthorization()
        onChange?()
    }

    func requestRemindersAccess() async {
        do {
            let granted = try await store.requestFullAccessToReminders()
            lastError = granted ? nil : "提醒事项访问未获允许；本地待办仍然可用。"
        } catch { lastError = error.localizedDescription }
        refreshAuthorization()
        onChange?()
    }

    func fetchEvents(from: Date, to: Date, calendarIDs: Set<String>) -> [CalendarEvent] {
        guard canReadEvents, !calendarIDs.isEmpty, from < to,
              from.timeIntervalSinceReferenceDate.isFinite, to.timeIntervalSinceReferenceDate.isFinite else { return [] }
        let selected = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: selected)
        return store.events(matching: predicate).filter { $0.status != .canceled }.map { event in
            let value = map(event)
            remember(value, itemID: event.calendarItemIdentifier)
            return value
        }.sorted { $0.start < $1.start }
    }

    func fetchReminders(calendarIDs: Set<String>) async throws -> [CalendarEvent] {
        guard canReadReminders, !calendarIDs.isEmpty else { return [] }
        let selected = store.calendars(for: .reminder).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: selected)
        let records: [EKReminder] = try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: SystemCalendarError.unavailable) }
            }
        }
        // Permissions may be revoked while the asynchronous fetch is running.
        guard canReadReminders else { return [] }
        return records.map { reminder in
            let value = map(reminder)
            remember(value, itemID: reminder.calendarItemIdentifier)
            return value
        }.sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            if $0.hasDueDate != $1.hasDueDate { return $0.hasDueDate }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    @discardableResult
    func save(_ event: CalendarEvent, toCalendarID: String?) throws -> CalendarEvent {
        try performWrite {
            try validate(event)
            if event.isExternal {
                guard event.externalKind == (event.isTask ? "appleReminders" : "appleCalendar") else {
                    throw SystemCalendarError.invalid("不能把已有的 Apple 日程转换成提醒事项，或反向转换。")
                }
                if let toCalendarID, toCalendarID != event.externalCalendarID {
                    throw SystemCalendarError.invalid("第一版请在 Apple 应用中移动已有记录的日历或清单。")
                }
                let baseline = try snapshot(for: event)
                guard event.repeatRule == baseline.value.repeatRule else {
                    throw SystemCalendarError.invalid("已有 Apple 记录的重复规则请在系统应用中修改。")
                }
                if event.isTask {
                    let item = try currentReminder(for: event, baseline: baseline)
                    apply(event, to: item, baseline: baseline.value)
                    try store.save(item, commit: true)
                    return rememberSaved(map(item), itemID: item.calendarItemIdentifier, wasCreated: false)
                } else {
                    let item = try currentEvent(for: event, baseline: baseline)
                    apply(event, to: item, baseline: baseline.value)
                    try store.save(item, span: .thisEvent, commit: true)
                    return rememberSaved(map(item), itemID: item.calendarItemIdentifier, wasCreated: false)
                }
            } else {
                let calendar = try writableCalendar(id: toCalendarID, isTask: event.isTask)
                if event.isTask {
                    let item = EKReminder(eventStore: store)
                    item.calendar = calendar
                    apply(event, to: item, baseline: nil)
                    try store.save(item, commit: true)
                    return rememberSaved(map(item), itemID: item.calendarItemIdentifier, wasCreated: true)
                } else {
                    let item = EKEvent(eventStore: store)
                    item.calendar = calendar
                    apply(event, to: item, baseline: nil)
                    try store.save(item, span: .thisEvent, commit: true)
                    return rememberSaved(map(item), itemID: item.calendarItemIdentifier, wasCreated: true)
                }
            }
        }
    }

    /// Compensate a failed local-to-Apple transfer, never an ordinary edit.
    /// The exact receipt returned by a new save and its unchanged system record
    /// are both required. A failed check leaves the receipt available for the
    /// caller to report/retry cleanup without creating another Apple record.
    func rollbackCreated(_ value: CalendarEvent) throws {
        try performWrite {
            let receipt = try creationReceipt(for: value)
            if value.externalKind == "appleCalendar" {
                let item = try currentEvent(for: value, baseline: receipt)
                // The receipt always points to the first occurrence created by
                // this process. `.thisEvent` would leave the rest of a newly
                // created repeating series behind after a transfer fails.
                let span: EKSpan = value.externalRecurring == true ? .futureEvents : .thisEvent
                try store.remove(item, span: span, commit: true)
            } else if value.externalKind == "appleReminders" {
                let item = try currentReminder(for: value, baseline: receipt)
                try store.remove(item, commit: true)
            } else {
                throw SystemCalendarError.invalid("这条记录不是可回滚的 Apple 创建回执。")
            }
            createdReceipts.removeValue(forKey: value.id)
            snapshots.removeValue(forKey: snapshotKey(value))
        }
    }

    /// Check before removing a transfer's local copy, including cleanup retries.
    /// Another application may have edited or deleted the Apple copy since its
    /// creation. This method only reads; failed checks must keep the local copy.
    func validateCreatedReceipt(_ value: CalendarEvent) throws {
        let receipt = try creationReceipt(for: value)
        if value.externalKind == "appleCalendar" {
            _ = try currentEvent(for: value, baseline: receipt)
        } else if value.externalKind == "appleReminders" {
            _ = try currentReminder(for: value, baseline: receipt)
        } else {
            throw SystemCalendarError.invalid("这条记录不是可验证的 Apple 创建回执。")
        }
    }

    private func creationReceipt(for value: CalendarEvent) throws -> Snapshot {
        guard let receipt = createdReceipts[value.id], receipt.value == value else {
            throw SystemCalendarError.invalid("无法确认这是本次新建的系统记录，请检查 Apple 来源中的记录；本地副本将保留。")
        }
        return receipt
    }

    /// Call after ordinary creation, or after a transfer's local deletion has
    /// succeeded. Fetching or editing existing records never creates a receipt.
    func finishCreationReceipt(_ value: CalendarEvent) {
        guard createdReceipts[value.id]?.value == value else { return }
        createdReceipts.removeValue(forKey: value.id)
    }

    private func rememberSaved(_ value: CalendarEvent, itemID: String, wasCreated: Bool) -> CalendarEvent {
        remember(value, itemID: itemID)
        if wasCreated { createdReceipts[value.id] = Snapshot(value: value, calendarItemID: itemID) }
        return value
    }

    func delete(_ event: CalendarEvent) throws {
        try performWrite {
            let baseline = try snapshot(for: event)
            if event.externalKind == "appleReminders" {
                try store.remove(try currentReminder(for: event, baseline: baseline), commit: true)
            } else if event.externalKind == "appleCalendar" {
                try store.remove(try currentEvent(for: event, baseline: baseline), span: .thisEvent, commit: true)
            } else { throw SystemCalendarError.missing }
        }
    }

    func setCompleted(_ event: CalendarEvent, completed: Bool) throws {
        try performWrite {
            guard event.externalKind == "appleReminders" else {
                throw SystemCalendarError.invalid("只有提醒事项可以标记完成。")
            }
            let item = try currentReminder(for: event, baseline: snapshot(for: event))
            // No title, alarm, deadline or other unrelated field is touched.
            item.isCompleted = completed
            try store.save(item, commit: true)
        }
    }

    private func performWrite<Result>(_ operation: () throws -> Result) throws -> Result {
        do {
            let result = try operation()
            lastError = nil
            onChange?()
            return result
        } catch {
            // Discard unsaved EventKit mutations after an unsuccessful save.
            store.reset()
            lastError = error.localizedDescription
            refreshAuthorization()
            throw error
        }
    }

    private func writableCalendar(id: String?, isTask: Bool) throws -> EKCalendar {
        guard isTask ? canReadReminders : canReadEvents else {
            throw SystemCalendarError.permission(isTask ? "提醒事项" : "日历")
        }
        guard let id else { throw SystemCalendarError.invalid("请先选择要保存到的 Apple 日历或提醒事项清单。") }
        guard let calendar = store.calendars(for: isTask ? .reminder : .event).first(where: { $0.calendarIdentifier == id }) else {
            throw SystemCalendarError.missing
        }
        guard calendar.allowsContentModifications else { throw SystemCalendarError.readOnly("这个日历或清单为只读，无法修改。") }
        return calendar
    }

    private func currentEvent(for edited: CalendarEvent, baseline: Snapshot) throws -> EKEvent {
        let calendar = try writableCalendar(id: edited.externalCalendarID, isTask: false)
        guard let identifier = edited.externalID else { throw SystemCalendarError.missing }
        let original = baseline.value
        var item: EKEvent?
        if original.externalRecurring == true {
            guard let occurrence = original.externalOccurrenceDate else { throw SystemCalendarError.stale }
            // event(withIdentifier:) may return the series master. Query the
            // captured occurrence's interval and match its ORIGINAL date instead.
            let margin: TimeInterval = 86_400
            let lower = min(original.start, occurrence).addingTimeInterval(-margin)
            let upper = max(original.end, occurrence).addingTimeInterval(margin)
            let predicate = store.predicateForEvents(withStart: lower, end: upper, calendars: [calendar])
            item = store.events(matching: predicate).first {
                ($0.eventIdentifier == identifier || $0.calendarItemIdentifier == baseline.calendarItemID)
                    && sameDate($0.occurrenceDate, occurrence)
                    && $0.calendar.calendarIdentifier == calendar.calendarIdentifier
            }
        } else {
            item = store.event(withIdentifier: identifier)
        }
        guard let item, item.calendar.calendarIdentifier == calendar.calendarIdentifier else { throw SystemCalendarError.missing }
        if original.externalRecurring == true, !sameDate(item.occurrenceDate, original.externalOccurrenceDate) {
            throw SystemCalendarError.stale
        }
        let current = map(item)
        try checkCurrent(current, original: original, edited: edited)
        return item
    }

    private func currentReminder(for edited: CalendarEvent, baseline: Snapshot) throws -> EKReminder {
        let calendar = try writableCalendar(id: edited.externalCalendarID, isTask: true)
        guard let identifier = edited.externalID,
              let item = store.calendarItem(withIdentifier: identifier) as? EKReminder,
              item.calendar.calendarIdentifier == calendar.calendarIdentifier else { throw SystemCalendarError.missing }
        try checkCurrent(map(item), original: baseline.value, edited: edited)
        return item
    }

    private func checkCurrent(_ current: CalendarEvent, original: CalendarEvent, edited: CalendarEvent) throws {
        guard current.externalReadOnly != true else {
            throw SystemCalendarError.readOnly(current.externalReadOnlyReason ?? "这条系统记录为只读。")
        }
        guard sameDate(current.externalModifiedAt, edited.externalModifiedAt), current == original else {
            throw SystemCalendarError.stale
        }
    }

    private func snapshot(for event: CalendarEvent) throws -> Snapshot {
        guard event.isExternal, let snapshot = snapshots[snapshotKey(event)],
              snapshot.value.externalID == event.externalID,
              snapshot.value.externalCalendarID == event.externalCalendarID,
              sameDate(snapshot.value.externalOccurrenceDate, event.externalOccurrenceDate) else {
            throw SystemCalendarError.stale
        }
        return snapshot
    }

    private func remember(_ event: CalendarEvent, itemID: String) {
        if snapshots.count > 12_000 { snapshots.removeAll() }
        // A provider can emit the same lastModifiedDate for two rapid changes.
        // Keep the first baseline in that case, conservatively rejecting drafts
        // rather than replacing the baseline under an already-open editor.
        let key = snapshotKey(event)
        if snapshots[key] == nil { snapshots[key] = Snapshot(value: event, calendarItemID: itemID) }
    }

    private func snapshotKey(_ event: CalendarEvent) -> String {
        "\(event.id.uuidString)|\(event.externalModifiedAt?.timeIntervalSinceReferenceDate.description ?? "nil")"
    }

    private func map(_ item: EKEvent) -> CalendarEvent {
        let recurring = item.hasRecurrenceRules || item.isDetached
        let occurrence: Date? = recurring ? (item.occurrenceDate ?? item.startDate) : nil
        var value = CalendarEvent(
            id: stableID("event|\(item.calendar.calendarIdentifier)|\(item.eventIdentifier ?? item.calendarItemIdentifier)|\(occurrence?.timeIntervalSinceReferenceDate.description ?? "single")"),
            title: item.title ?? "未命名日程", start: item.startDate,
            end: item.endDate, notes: item.notes ?? "", isAllDay: item.isAllDay,
            repeatRule: .none, reminderMinutes: simpleReminderMinutes(item.alarms)
        )
        value.externalID = item.eventIdentifier
        value.externalCalendarID = item.calendar.calendarIdentifier
        value.externalCalendarTitle = item.calendar.title
        value.externalKind = "appleCalendar"
        value.externalModifiedAt = item.lastModifiedDate
        value.externalOccurrenceDate = occurrence
        value.externalRecurring = recurring
        value.location = item.location
        value.externalReadOnlyReason = readOnlyReason(item)
        value.externalReadOnly = value.externalReadOnlyReason != nil
        return value
    }

    private func map(_ item: EKReminder) -> CalendarEvent {
        let due = item.dueDateComponents
        let hasTime = due?.hour != nil || due?.minute != nil
        // Undated tasks use a stable inert date; hasDueDate excludes them from
        // timeline/notifications. Never substitute "today" on each refresh.
        let date = due.flatMap { SystemReminderDateCodec.date(from: $0) } ?? Date(timeIntervalSinceReferenceDate: 0)
        var value = CalendarEvent(
            id: stableID("reminder|\(item.calendar.calendarIdentifier)|\(item.calendarItemIdentifier)"),
            title: item.title ?? "未命名待办", start: date, end: date,
            notes: item.notes ?? "", isAllDay: !hasTime, repeatRule: .none,
            reminderMinutes: simpleReminderMinutes(item.alarms),
            isCompleted: item.isCompleted, isTask: true
        )
        value.externalID = item.calendarItemIdentifier
        value.externalCalendarID = item.calendar.calendarIdentifier
        value.externalCalendarTitle = item.calendar.title
        value.externalKind = "appleReminders"
        value.externalModifiedAt = item.lastModifiedDate
        value.externalRecurring = item.hasRecurrenceRules
        value.taskHasDueDate = due != nil
        value.taskDueHasTime = hasTime
        value.location = item.location
        value.externalReadOnlyReason = item.hasRecurrenceRules
            ? "重复提醒事项请在 Apple 提醒事项中编辑或完成，以保留原来的重复规则。"
            : readOnlyReason(item)
        value.externalReadOnly = value.externalReadOnlyReason != nil
        return value
    }

    private func readOnlyReason(_ item: EKCalendarItem) -> String? {
        if !item.calendar.allowsContentModifications { return "来源日历或清单为只读。" }
        if item.hasAttendees { return "含有参与者的共享日程请在 Apple 日历中修改，避免意外发送邀请或取消通知。" }
        if item.lastModifiedDate == nil { return "系统未提供修改版本，请在 Apple 应用中编辑这条记录。" }
        return nil
    }

    private func apply(_ value: CalendarEvent, to item: EKEvent, baseline: CalendarEvent?) {
        applyCommon(value, to: item, baseline: baseline)
        if baseline == nil || value.start != baseline?.start { item.startDate = value.start }
        if baseline == nil || value.end != baseline?.end { item.endDate = value.end }
        if baseline == nil || value.isAllDay != baseline?.isAllDay { item.isAllDay = value.isAllDay }
        // Existing Apple recurrences are already expanded into occurrences.
        // Their hidden series rule is never replaced by the UI's `.none`.
        if baseline == nil { item.recurrenceRules = recurrenceRules(value.repeatRule) }
    }

    private func apply(_ value: CalendarEvent, to item: EKReminder, baseline: CalendarEvent?) {
        applyCommon(value, to: item, baseline: baseline)
        let changedDue = baseline == nil || value.hasDueDate != baseline?.hasDueDate
            || (value.hasDueDate && (value.start != baseline?.start || value.taskDueHasTime != baseline?.taskDueHasTime))
        if changedDue {
            let previousDue = item.dueDateComponents
            let previousStart = item.startDateComponents
            if value.hasDueDate {
                let timed = value.taskDueHasTime ?? !value.isAllDay
                let due = SystemReminderDateCodec.components(
                    for: value.start, hasTime: timed, originalTimeZone: previousDue?.timeZone
                )
                item.dueDateComponents = due
                if baseline == nil || previousStart == previousDue { item.startDateComponents = due }
            } else {
                item.dueDateComponents = nil
                if previousStart == previousDue { item.startDateComponents = nil }
            }
        }
        if baseline == nil {
            item.recurrenceRules = value.hasDueDate ? recurrenceRules(value.repeatRule) : nil
            if !value.hasDueDate { item.alarms = nil }
        }
        if baseline == nil || value.isCompleted != baseline?.isCompleted { item.isCompleted = value.isCompleted }
    }

    private func applyCommon(_ value: CalendarEvent, to item: EKCalendarItem, baseline: CalendarEvent?) {
        if baseline == nil || value.title != baseline?.title { item.title = value.title }
        if baseline == nil || value.notes != baseline?.notes { item.notes = value.notes.isEmpty ? nil : value.notes }
        if baseline == nil || value.location != baseline?.location { item.location = value.location }
        if baseline == nil || value.reminderMinutes != baseline?.reminderMinutes {
            item.alarms = value.reminderMinutes.map { [EKAlarm(relativeOffset: -Double($0) * 60)] }
        }
    }

    private func recurrenceRules(_ rule: EventRepeat) -> [EKRecurrenceRule]? {
        guard rule != .none else { return nil }
        return [EKRecurrenceRule(recurrenceWith: rule == .daily ? .daily : .weekly, interval: 1, end: nil)]
    }

    private func simpleReminderMinutes(_ alarms: [EKAlarm]?) -> Int? {
        guard let alarms, alarms.count == 1, let alarm = alarms.first,
              alarm.absoluteDate == nil, alarm.structuredLocation == nil,
              alarm.relativeOffset.isFinite, alarm.relativeOffset <= 0,
              alarm.type == .display || alarm.type == .audio else { return nil }
        let minutes = -alarm.relativeOffset / 60
        guard minutes.rounded() == minutes, minutes < Double(Int.max) else { return nil }
        return Int(minutes)
    }

    private func validate(_ event: CalendarEvent) throws {
        guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SystemCalendarError.invalid("请填写日程或待办名称。")
        }
        guard event.start.timeIntervalSinceReferenceDate.isFinite,
              event.end.timeIntervalSinceReferenceDate.isFinite,
              event.isTask || event.end > event.start else {
            throw SystemCalendarError.invalid("结束时间需要晚于开始时间。")
        }
        if let minutes = event.reminderMinutes, minutes < 0 {
            throw SystemCalendarError.invalid("提醒提前量不能小于零。")
        }
        if !event.isExternal, event.isTask, !event.hasDueDate, event.repeatRule != .none {
            throw SystemCalendarError.invalid("重复提醒事项需要设置截止日期。")
        }
    }

    private func permissionLabel(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess: return "已连接 · 完整访问"
        case .writeOnly: return "仅可添加 · 读取需完整访问"
        case .denied: return "已拒绝 · 可在系统设置中开启"
        case .restricted: return "系统限制访问"
        case .notDetermined: return "未连接"
        @unknown default: return "权限状态未知"
        }
    }

    private func choice(_ calendar: EKCalendar, isReminder: Bool) -> SystemCalendarChoice {
        let color = NSColor(cgColor: calendar.cgColor)?.usingColorSpace(.deviceRGB)
        let red = UInt(((color?.redComponent ?? 0.30) * 255).rounded())
        let green = UInt(((color?.greenComponent ?? 0.52) * 255).rounded())
        let blue = UInt(((color?.blueComponent ?? 0.43) * 255).rounded())
        return SystemCalendarChoice(
            id: calendar.calendarIdentifier, title: calendar.title,
            sourceTitle: calendar.source.title, isReminder: isReminder,
            isWritable: calendar.allowsContentModifications,
            colorHex: (red << 16) | (green << 8) | blue
        )
    }

    private func sameDate(_ lhs: Date?, _ rhs: Date?) -> Bool { lhs == rhs }

    private func stableID(_ key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
