import SwiftUI
import Combine
import LingxiCore

struct ChatMessage: Identifiable {
    let id = UUID()
    var isUser: Bool
    var text: String
    var containsSystemData = false
}

enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case month = "月", week = "周", day = "日"
    var id: String { rawValue }
}

@MainActor final class AppStore: ObservableObject {
    @Published var selectedDate = Date() { didSet { scheduleSystemReload() } }
    @Published var visibleMonth = Date() { didSet { scheduleSystemReload() } }
    @Published var events: [CalendarEvent] = []
    @Published var section = "月历"
    @Published var calendarMode: CalendarDisplayMode = .month
    @Published var showingConnections = false
    @Published var systemEvents: [CalendarEvent] = []
    @Published var systemReminders: [CalendarEvent] = []
    @Published var systemLoading = false
    @Published var systemSyncMessage: String?
    @Published var systemLastRefresh: Date?
    @Published var selectedCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: "selectedCalendarIDs") ?? [])
    @Published var selectedReminderIDs = Set(UserDefaults.standard.stringArray(forKey: "selectedReminderIDs") ?? [])
    @Published private(set) var defaultEventDestination = UserDefaults.standard.string(forKey: "defaultEventDestination") ?? "local"
    @Published private(set) var defaultTaskDestination = UserDefaults.standard.string(forKey: "defaultTaskDestination") ?? "local"
    @Published var cloudIncludeSystemData = UserDefaults.standard.bool(forKey: "cloudIncludeSystemData")
    @Published var editorEvent: CalendarEvent?
    @Published var showingChat = false
    @Published var showingSettings = false
    @Published var showingSources = false
    @Published var petVisible = UserDefaults.standard.object(forKey: "petVisible") as? Bool ?? true
    @Published var status: String?
    @Published var storageError: String?
    @Published var messages: [ChatMessage] = [ChatMessage(isUser: false, text: "我是阿灵，陪你把日子安排得从容一点。\n\n试着说：提醒我明天下午三点开会。你也可以选一个日子，和我聊聊那天的安排。")]
    @Published var draft: ParsedEvent?
    @Published var isThinking = false
    @Published var notificationStatus = "尚未启用"
    @Published var cloudEnabled = UserDefaults.standard.bool(forKey: "cloudEnabled")
    @Published var endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? ""
    @Published var modelName = UserDefaults.standard.string(forKey: "modelName") ?? ""
    let calendar = CalendarEngine()
    let birthProfiles: BirthProfileStore
    let scheduler = EventScheduler()
    let planner = PlanningEngine()
    let system = SystemCalendarService()
    private let localTransfers = LocalEventTransfer<CalendarEvent>()
    private var systemTask: Task<Void, Never>?
    private var systemObservation: AnyCancellable?
    private var profileObservation: AnyCancellable?
    private var systemRevision = 0
    let repository: EventRepository
    let notifications = NotificationService()
    private var saveBlocked = false
    private var conversationTask: Task<Void, Never>?
    var showPetAction: (() -> Void)?
    var showMainAction: (() -> Void)?
    var showChatAction: (() -> Void)?

    var isPreviewMode: Bool { Bundle.main.bundleIdentifier == "com.lingxing.calendar.preview" }
    init() {
        #if DEBUG
        let previewPath = Bundle.main.object(forInfoDictionaryKey: "LingxingPreviewDataFile") as? String
        let dataURL = previewPath.map { URL(fileURLWithPath: $0) } ?? EventRepository.defaultURL()
        #else
        let dataURL = EventRepository.defaultURL()
        #endif
        repository = EventRepository(fileURL: dataURL)
        let profileURL = Bundle.main.bundleIdentifier == "com.lingxing.calendar.preview"
            ? dataURL.deletingLastPathComponent().appendingPathComponent("preview-profiles.json")
            : BirthProfileRepository.defaultURL()
        birthProfiles = BirthProfileStore(fileURL: profileURL)
        do { events = try repository.load() }
        catch { storageError = "本地日程读取失败，已保留原文件。\n\(error.localizedDescription)"; saveBlocked = true }
        notifications.onStatus = { [weak self] text in self?.notificationStatus = text }
        notifications.onOpen = { [weak self] id, start in
            guard let self, let event = self.events.first(where: { $0.id.uuidString == id }) else { return }
            self.select(start ?? event.start); self.showMainAction?()
        }
        notifications.onComplete = { [weak self] id in
            guard let self, let task = self.events.first(where: { $0.id.uuidString == id && $0.isTask && !$0.isCompleted }) else { return false }
            var completed = task; completed.isCompleted = true
            return self.save(completed)
        }
        notifications.onShowCalendar = { [weak self] in self?.showMainAction?() }
        systemObservation = system.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        profileObservation = birthProfiles.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        system.onChange = { [weak self] in self?.scheduleSystemReload() }
        Task { await refreshNotifications(requestPermission: false); await reloadSystemData() }
    }

    var allEvents: [CalendarEvent] { events + systemEvents + systemReminders }
    var occurrences: [EventOccurrence] { occurrences(on: selectedDate) }
    var todayCount: Int { occurrences(on: Date()).count }
    var pendingTasks: [CalendarEvent] { allEvents.filter { $0.isTask && !$0.isCompleted }.sorted { $0.hasDueDate && !$1.hasDueDate || $0.hasDueDate == $1.hasDueDate && $0.start < $1.start } }
    var sourceCount: Int { selectedCalendarIDs.count + selectedReminderIDs.count }
    var destinationCalendars: [SystemCalendarChoice] {
        system.calendars.filter { $0.isWritable }
    }
    func defaultDestination(isTask: Bool) -> String { isTask ? defaultTaskDestination : defaultEventDestination }
    func destinationLabel(_ id: String, isTask: Bool) -> String {
        guard id != "local" else { return "仅灵性日历（本地）" }
        guard let choice = destinationCalendars.first(where: { $0.id == id && $0.isReminder == isTask }) else { return "Apple 保存位置暂不可用" }
        return "\(isTask ? "Apple 提醒事项" : "Apple 日历") · \(choice.title) · \(choice.sourceTitle)"
    }
    func setDefaultDestination(_ id: String, isTask: Bool) {
        guard id == "local" || destinationCalendars.contains(where: { $0.id == id && $0.isReminder == isTask }) else { return }
        if isTask { defaultTaskDestination = id } else { defaultEventDestination = id }
        UserDefaults.standard.set(id, forKey: isTask ? "defaultTaskDestination" : "defaultEventDestination")
        if let choice = destinationCalendars.first(where: { $0.id == id }) { setSource(choice, selected: true) }
    }
    func pendingTransfer(for event: CalendarEvent) -> CalendarEvent? {
        localTransfers.pendingReceipt(for: event.id)
    }
    func isPendingTransferDestination(_ event: CalendarEvent) -> Bool {
        event.isExternal && localTransfers.pendingTransfers.values.contains { $0.id == event.id }
    }
    func occurrences(on date: Date) -> [EventOccurrence] {
        let from = calendar.gregorian.startOfDay(for: date)
        return scheduler.occurrences(of: allEvents, from: from, to: calendar.gregorian.date(byAdding: .day, value: 1, to: from)!)
    }
    func select(_ date: Date) { selectedDate = date; visibleMonth = date }
    func moveMonth(_ offset: Int) { visibleMonth = calendar.gregorian.date(byAdding: .month, value: offset, to: visibleMonth)! }
    func movePeriod(_ offset: Int) {
        switch calendarMode {
        case .month: moveMonth(offset)
        case .week: select(calendar.gregorian.date(byAdding: .day, value: offset * 7, to: selectedDate)!)
        case .day: select(calendar.gregorian.date(byAdding: .day, value: offset, to: selectedDate)!)
        }
    }
    func newEvent(isTask: Bool = false, at date: Date? = nil, durationMinutes: Int = 60) {
        var start = date ?? calendar.gregorian.date(bySettingHour: 15, minute: 0, second: 0, of: selectedDate)!
        if date == nil, calendar.gregorian.isDateInToday(selectedDate), start < Date() {
            start = calendar.gregorian.date(byAdding: .hour, value: 1, to: Date())!
        }
        var event = CalendarEvent(title: "", start: start, end: start.addingTimeInterval(Double(durationMinutes * 60)), isTask: isTask)
        if isTask { event.taskHasDueDate = false; event.taskDueHasTime = false; event.reminderMinutes = nil }
        editorEvent = event
    }
    func scheduleTask(_ task: CalendarEvent) {
        let start = calendar.gregorian.date(bySettingHour: 15, minute: 0, second: 0, of: selectedDate)!
        editorEvent = CalendarEvent(title: task.title, start: start, end: start.addingTimeInterval(1800), notes: "为待办安排的专注时间。来源：\(task.sourceLabel)\n\(task.notes)", reminderMinutes: 10)
    }
    func conflicts(for event: CalendarEvent) -> [EventOccurrence] {
        guard !event.isTask, event.end > event.start else { return [] }
        let external = system.fetchEvents(from: calendar.gregorian.startOfDay(for: event.start), to: event.end.addingTimeInterval(1), calendarIDs: selectedCalendarIDs)
        return planner.conflicts(for: event, among: events + external)
    }
    func proposeMove(_ occurrence: EventOccurrence, to start: Date) {
        guard occurrence.event.externalReadOnly != true else { status = occurrence.event.externalReadOnlyReason ?? "这个来源只可查看"; return }
        var updated = occurrence.event
        let duration = occurrence.end.timeIntervalSince(occurrence.start)
        if updated.repeatRule != .none && !updated.isExternal {
            status = "本地重复日程请通过编辑器调整整个系列，暂不支持拖动单次。"
            return
        } else { updated.start = start; updated.end = start.addingTimeInterval(duration) }
        editorEvent = updated
    }
    @discardableResult func save(_ event: CalendarEvent, toCalendarID destination: String? = nil) -> Bool {
        guard !isPendingTransferDestination(event) else { status = "请先打开本地副本完成转入整理，再修改 Apple 日程。"; return false }
        if !event.isExternal, let completed = localTransfers.completedReceipt(for: event.id) {
            status = "这条日程已转入\(completed.sourceLabel)。请关闭旧编辑器，从 Apple 来源重新打开后修改。"
            return false
        }
        if !event.isExternal, let destination, events.contains(where: { $0.id == event.id }) {
            return transferLocal(event, toCalendarID: destination)
        }
        guard pendingTransfer(for: event) == nil else { status = "这条日程已写入 Apple，请先完成本地副本整理。"; return false }
        if event.isExternal || destination != nil {
            do {
                let saved = try system.save(event, toCalendarID: destination)
                system.finishCreationReceipt(saved)
                showSavedSystemEvent(saved)
                status = "已保存到\(saved.sourceLabel)：\(event.title)"
                scheduleSystemReload(); return true
            } catch { status = "未保存：\(error.localizedDescription)"; return false }
        }
        guard !saveBlocked else { status = "日程文件读取异常，暂不可写入。请在设置中查看数据位置。"; return false }
        var updated = events
        if let index = updated.firstIndex(where: { $0.id == event.id }) { updated[index] = event }
        else { updated.append(event) }
        return persist(updated, message: "已保存到本地：\(event.title)（不会写入 Apple）")
    }
    private func showSavedSystemEvent(_ event: CalendarEvent) {
        if let choice = destinationCalendars.first(where: { $0.id == event.externalCalendarID }) { setSource(choice, selected: true) }
        if event.isTask { systemReminders.removeAll { $0.id == event.id }; systemReminders.append(event) }
        else { systemEvents.removeAll { $0.id == event.id }; systemEvents.append(event) }
    }
    private func transferLocal(_ event: CalendarEvent, toCalendarID destination: String) -> Bool {
        let pending = pendingTransfer(for: event)
        if let pending, pending.externalCalendarID != destination { status = "这条日程已写入\(pending.sourceLabel)，请先完成本地副本整理，不能再次选择其他来源。"; return false }
        guard !event.isTask || event.repeatRule == .none else { status = "重复本地待办暂不支持转入 Apple，请在 Apple 提醒事项中设置重复规则。"; return false }
        guard !saveBlocked else { status = "本地文件不可写，尚未转入 Apple。"; return false }
        // Check local persistence before creating any system record.
        do { try repository.save(events) }
        catch { status = pending == nil ? "本地文件不可写，尚未转入 Apple：\(error.localizedDescription)" : "已写入 Apple，但本地副本仍未整理：\(error.localizedDescription)"; return false }
        var receipt = pending
        let result = localTransfers.transfer(localID: event.id, create: {
            let saved = try system.save(event, toCalendarID: destination)
            receipt = saved
            return saved
        }, removeLocal: {
            guard let receipt else { throw SystemCalendarError.stale }
            // Never discard the surviving local copy if Apple was deleted or
            // changed while a previous cleanup was waiting to be retried.
            try system.validateCreatedReceipt(receipt)
            let remaining = events.filter { $0.id != event.id }
            try repository.save(remaining)
            events = remaining
        }, rollback: { saved in try system.rollbackCreated(saved) })
        switch result {
        case .saved(let saved):
            system.finishCreationReceipt(saved)
            showSavedSystemEvent(saved)
            status = "已转入\(saved.sourceLabel)：\(saved.title)。之后在原来源中修改。"
            Task { await refreshNotifications(requestPermission: false) }
            scheduleSystemReload(); return true
        case .failed(_, let error):
            status = "未转入 Apple，本地日程仍保留：\(error.localizedDescription)"
        case .pendingCleanup(let saved, let error, _):
            showSavedSystemEvent(saved)
            status = "已写入\(saved.sourceLabel)，但本地副本整理失败：\(error.localizedDescription)。再次保存只整理本地副本，不会重复新建。"
            scheduleSystemReload()
        }
        return false
    }
    @discardableResult func delete(_ event: CalendarEvent) -> Bool {
        guard !isPendingTransferDestination(event) else { status = "请先打开本地副本完成转入整理，再删除 Apple 日程。"; return false }
        guard pendingTransfer(for: event) == nil else { status = "请先在编辑器中完成转入后的本地副本整理。"; return false }
        if event.isExternal {
            do { try system.delete(event); scheduleSystemReload(); status = "已从系统来源删除「\(event.title)」"; return true }
            catch { status = "未删除：\(error.localizedDescription)"; return false }
        }
        return persist(events.filter { $0.id != event.id }, message: "已删除「\(event.title)」")
    }
    func toggleCompleted(_ event: CalendarEvent) {
        guard !isPendingTransferDestination(event) else { status = "请先打开本地副本完成转入整理，再修改完成状态。"; return }
        if event.isExternal {
            do { try system.setCompleted(event, completed: !event.isCompleted); scheduleSystemReload(); status = event.isCompleted ? "已恢复待办" : "已完成待办" }
            catch { status = "未修改：\(error.localizedDescription)" }
        } else { var changed = event; changed.isCompleted.toggle(); _ = save(changed) }
    }
    func setSource(_ choice: SystemCalendarChoice, selected: Bool) {
        if choice.isReminder { if selected { selectedReminderIDs.insert(choice.id) } else { selectedReminderIDs.remove(choice.id) } }
        else { if selected { selectedCalendarIDs.insert(choice.id) } else { selectedCalendarIDs.remove(choice.id) } }
        UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: "selectedCalendarIDs")
        UserDefaults.standard.set(Array(selectedReminderIDs), forKey: "selectedReminderIDs")
        // Remove deselected records immediately, including any in-flight old load.
        systemEvents.removeAll { !selectedCalendarIDs.contains($0.externalCalendarID ?? "") }
        systemReminders.removeAll { !selectedReminderIDs.contains($0.externalCalendarID ?? "") }
        scheduleSystemReload()
    }
    func scheduleSystemReload() {
        systemRevision += 1
        systemTask?.cancel()
        systemTask = Task { try? await Task.sleep(for: .milliseconds(250)); guard !Task.isCancelled else { return }; await reloadSystemData() }
    }
    func reloadSystemData() async {
        systemRevision += 1
        let revision = systemRevision
        system.refreshAuthorization()
        systemLoading = true
        defer { if revision == systemRevision { systemLoading = false } }
        let grid = calendar.monthDays(containing: visibleMonth)
        let week = planner.weekDays(containing: selectedDate)
        let from = min(grid.first ?? selectedDate, week.first ?? selectedDate)
        let to = calendar.gregorian.date(byAdding: .day, value: 1, to: max(grid.last ?? selectedDate, week.last ?? selectedDate))!
        let calendarIDs = selectedCalendarIDs, reminderIDs = selectedReminderIDs
        let loadedEvents = system.fetchEvents(from: from, to: to, calendarIDs: calendarIDs)
        if !system.canReadEvents { systemEvents = [] }
        if !system.canReadReminders { systemReminders = [] }
        do {
            let loadedReminders = try await system.fetchReminders(calendarIDs: reminderIDs)
            guard !Task.isCancelled, revision == systemRevision else { return }
            systemEvents = system.canReadEvents ? loadedEvents : []; systemReminders = system.canReadReminders ? loadedReminders : []
            systemLastRefresh = Date(); systemSyncMessage = system.lastError
        } catch {
            guard revision == systemRevision else { return }
            systemEvents = system.canReadEvents ? loadedEvents : []; if !system.canReadReminders { systemReminders = [] }; systemSyncMessage = error.localizedDescription
        }
    }
    @discardableResult private func persist(_ updated: [CalendarEvent], message: String) -> Bool {
        guard !saveBlocked else { return false }
        do {
            try repository.save(updated)
            events = updated; status = message
            Task { await refreshNotifications(requestPermission: updated.contains { $0.reminderMinutes != nil && !$0.isCompleted }) }
            return true
        } catch { status = "保存失败：\(error.localizedDescription)"; return false }
    }
    func togglePet() {
        petVisible.toggle(); UserDefaults.standard.set(petVisible, forKey: "petVisible"); showPetAction?()
    }
    func refreshNotifications(requestPermission: Bool) async {
        guard !isPreviewMode else { notificationStatus = "隔离预览 · 不发送系统通知"; return }
        guard storageError == nil else { notificationStatus = "日程读取异常，保留已安排的系统提醒"; return }
        await notifications.refresh(events: events, requestPermission: requestPermission)
    }
    func saveSettings(enabled: Bool, endpoint newEndpoint: String, model: String, key: String) throws {
        let cleaned = newEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: cleaned)
        if enabled {
            guard let url, url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, !model.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw AssistantService.ServiceError.invalidConfiguration
            }
            if key.isEmpty && (KeychainCredential.read().isEmpty || URL(string: endpoint)?.host != url.host) {
                throw AssistantService.ServiceError.missingKey
            }
        }
        if !key.isEmpty { try KeychainCredential.save(key) }
        else if URL(string: endpoint)?.host != url?.host { KeychainCredential.delete() }
        cloudEnabled = enabled; endpoint = cleaned; modelName = model
        UserDefaults.standard.set(cloudEnabled, forKey: "cloudEnabled")
        UserDefaults.standard.set(endpoint, forKey: "endpoint")
        UserDefaults.standard.set(modelName, forKey: "modelName")
    }
    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        draft = nil
        messages.append(ChatMessage(isUser: true, text: text))
        switch NaturalLanguageParser().parse(text) {
        case .event(let parsed):
            draft = parsed
            messages.append(ChatMessage(isUser: false, text: "我整理好了这条日程。核对下方的日期、时间和提醒，确认后就会加入日历。"))
        case .needsClarification(let question):
            messages.append(ChatMessage(isUser: false, text: question + "\n请把补充信息和事项合在一句话里重新告诉我。"))
        case .notAnEvent:
            draft = nil
            if cloudEnabled { askCloud(text) }
            else { messages.append(ChatMessage(isUser: false, text: AdviceEngine().reply(to: text, on: selectedDate, eventTitles: occurrences.map { $0.event.title }), containsSystemData: occurrences.contains { $0.event.isExternal })) }
        }
    }
    private func askCloud(_ text: String) {
        isThinking = true
        let info = calendar.info(for: selectedDate)
        let contextEntries = occurrences.filter { !$0.event.isExternal || cloudIncludeSystemData }
        let context = "选中日期：\(DateText.day(selectedDate))，农历\(info.lunarDate)，\(info.yearGanZhi)。已登记事项：\(contextEntries.map { $0.event.title }.joined(separator: "、"))。所有日期为北京时间。"
        let sharesSystemData = cloudIncludeSystemData && contextEntries.contains { $0.event.isExternal }
        let history = Array(messages.filter { !$0.containsSystemData || cloudIncludeSystemData }.suffix(12))
        conversationTask = Task {
            defer { isThinking = false }
            do {
                let reply = try await AssistantService.reply(endpoint: endpoint, model: modelName, key: KeychainCredential.read(), messages: history, context: context)
                if !Task.isCancelled { messages.append(ChatMessage(isUser: false, text: reply, containsSystemData: sharesSystemData)) }
            } catch is CancellationError { }
            catch { messages.append(ChatMessage(isUser: false, text: "远程对话未完成：\(error.localizedDescription)\n你仍可使用本地日程指令和日期建议。")) }
        }
    }
    /// Returns a conflicted candidate for the chat's own editor sheet.
    func confirmDraft() -> CalendarEvent? {
        guard let draft else { return nil }
        let event = CalendarEvent(title: draft.title, start: draft.start, end: draft.start.addingTimeInterval(Double(draft.durationMinutes * 60)), notes: draft.notes, repeatRule: EventRepeat(rawValue: draft.repeatRule) ?? .none, reminderMinutes: draft.reminderMinutes < 0 ? nil : draft.reminderMinutes)
        if !conflicts(for: event).isEmpty {
            self.draft = nil
            messages.append(ChatMessage(isUser: false, text: "这个时段与已有安排重叠，请在日程编辑器中检查后确认保存。"))
            return event
        }
        let destination = defaultDestination(isTask: false)
        if save(event, toCalendarID: destination == "local" ? nil : destination) {
            select(event.start); self.draft = nil
            messages.append(ChatMessage(isUser: false, text: "已保存到\(destinationLabel(destination, isTask: false))：\(event.title)\n\(DateText.full(event.start))。"))
        } else {
            messages.append(ChatMessage(isUser: false, text: status ?? "这条日程尚未保存，请重试。"))
        }
        return nil
    }
    func askAboutEvent(_ event: CalendarEvent, on date: Date? = nil) {
        let day = date ?? event.start
        let info = calendar.info(for: day)
        let advice = AdviceEngine().advice(for: event.title, on: day)
        messages.append(ChatMessage(isUser: false, text: "「\(event.title)」的准备笺\n\n历法事实\n\(DateText.full(day))，农历\(info.lunarDate)，\(info.yearGanZhi)年 · \(info.dayGanZhi)日。\n\n传统文化\n\(advice.tradition)\n\n行动建议\n\(advice.action)", containsSystemData: event.isExternal))
        showChatAction?()
    }
    func askAboutDay() {
        let info = calendar.info(for: selectedDate)
        let advice = AdviceEngine().advice(for: occurrences.first?.event.title ?? "日常安排", on: selectedDate)
        messages.append(ChatMessage(isUser: false, text: "\(DateText.day(selectedDate)) · 农历\(info.lunarDate)\n\n历法事实\n\(info.yearGanZhi)年 · \(info.dayGanZhi)日\n\n传统文化\n\(advice.tradition)\n\n行动建议\n\(advice.action)"))
        showingChat = true
    }
}

enum DateText {
    static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
    static func day(_ date: Date) -> String { format(date, "M月d日 EEEE") }
    static func full(_ date: Date) -> String { format(date, "yyyy年M月d日 HH:mm") }
    static func time(_ date: Date) -> String { format(date, "HH:mm") }
}
