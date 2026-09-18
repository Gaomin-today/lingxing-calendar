import SwiftUI
import AppKit
import LingxiCore

@main enum LingxingApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = AppStore()
    var mainWindow: NSWindow!
    var petPanel: NSPanel?
    var chatWindow: NSWindow?
    var statusItem: NSStatusItem!
    private var reminderTimer: Timer?
    private var automationServer: AutomationSocketServer?
    private var automationRouter: AppAutomationRouter?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 880), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "灵性日历"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 1130, height: 720)
        window.contentView = NSHostingView(rootView: MainView(store: store).padding(.top, 22).background(Theme.paper))
        window.setFrameAutosaveName("LingxingMainWindow")
        if !window.setFrameUsingName("LingxingMainWindow") { window.center() }
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            var frame = window.frame
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
            window.setFrame(frame, display: false)
        }
        window.delegate = self
        mainWindow = window
        setupMenu()
        store.showMainAction = { [weak self] in self?.showMain() }
        store.showPetAction = { [weak self] in self?.updatePet() }
        store.showChatAction = { [weak self] in self?.openChat() }
        automationRouter = AppAutomationRouter(store: store)
        store.automationSettingsChanged = { [weak self] in self?.configureAutomation() }
        configureAutomation()
        showMain(); updatePet()
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in Task { @MainActor in guard let self else { return }; await self.store.refreshNotifications(requestPermission: false); await self.store.reloadSystemData() } }
        let menu = NSMenu()
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "关于灵性日历", action: #selector(about), keyEquivalent: ""); appMenu.addItem(.separator()); appMenu.addItem(withTitle: "偏好设置…", action: #selector(settings), keyEquivalent: ","); appMenu.addItem(.separator()); appMenu.addItem(withTitle: "退出灵性日历", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in appMenu.items where item.action == #selector(about) || item.action == #selector(settings) { item.target = self }
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let scheduleMenu = NSMenu(title: "日程")
        scheduleMenu.addItem(withTitle: "新建日程", action: #selector(newEvent), keyEquivalent: "n")
        scheduleMenu.addItem(withTitle: "和阿灵聊聊", action: #selector(openChat), keyEquivalent: "j")
        scheduleMenu.addItem(withTitle: "显示 / 隐藏桌面阿灵", action: #selector(togglePet), keyEquivalent: "")
        let calendarMenu = NSMenu(title: "日历视图")
        calendarMenu.addItem(withTitle: "年视图", action: #selector(showYearCalendar), keyEquivalent: "1")
        calendarMenu.addItem(withTitle: "月视图", action: #selector(showMonthCalendar), keyEquivalent: "2")
        calendarMenu.addItem(withTitle: "周视图", action: #selector(showWeekCalendar), keyEquivalent: "3")
        calendarMenu.addItem(withTitle: "日视图", action: #selector(showDayCalendar), keyEquivalent: "4")
        for item in calendarMenu.items { item.target = self; item.keyEquivalentModifierMask = [.command] }
        let calendarItem = NSMenuItem(title: "日历视图", action: nil, keyEquivalent: ""); calendarItem.submenu = calendarMenu; scheduleMenu.addItem(calendarItem)
        for item in scheduleMenu.items { item.target = self }
        let scheduleItem = NSMenuItem(title: "日程", action: nil, keyEquivalent: ""); scheduleItem.submenu = scheduleMenu; menu.addItem(scheduleItem)
        let edit = NSMenu(title: "编辑"); edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z"); edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"); edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"); edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"); edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editItem.submenu = edit; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
    @objc func newEvent() { showMain(); store.newEvent() }
    @objc func showYearCalendar() { showCalendar(.year) }
    @objc func showMonthCalendar() { showCalendar(.month) }
    @objc func showWeekCalendar() { showCalendar(.week) }
    @objc func showDayCalendar() { showCalendar(.day) }
    private func showCalendar(_ mode: CalendarDisplayMode) { showMain(); store.section = "日历"; store.calendarMode = mode }
    private func configureAutomation() {
        automationServer?.stop(); automationServer = nil
        guard store.automationEnabled, let router = automationRouter else { store.automationStatus = "本机 CLI 访问已关闭"; return }
        let server = AutomationSocketServer(path: AutomationSocket.defaultPath(preview: store.isPreviewMode)) { request in await router.handle(request) }
        do { try server.start(); automationServer = server; store.automationStatus = "已就绪 · 仅本机当前用户" }
        catch { store.automationStatus = "CLI 未启动：\(error.localizedDescription)" }
    }
    func applicationWillTerminate(_ notification: Notification) { automationServer?.stop() }
    @objc func showMain() { mainWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func settings() { showMain(); store.showingSettings = true }
    @objc func about() { showMain(); store.showingSources = true }
    @objc func togglePet() { store.togglePet() }
    @objc func openChat() {
        if chatWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 650), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "阿灵 · 灵性日历"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ChatView(store: store).padding(.top, 20).background(Theme.paper)); window.center(); chatWindow = window
        }
        chatWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func updatePet() {
        if store.petVisible {
            if petPanel == nil {
                let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 116, height: 136), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
                panel.contentView = NSHostingView(rootView: PetView(store: store, open: { [weak self] in self?.openChat() }))
                let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
                panel.setFrameOrigin(NSPoint(x: screen.maxX - 140, y: screen.minY + 60)); panel.setFrameAutosaveName("LingxingPet")
                petPanel = panel
            }
            petPanel?.orderFrontRegardless()
        } else { petPanel?.orderOut(nil) }
    }
    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: "灵性日历")
        let menu = NSMenu()
        menu.addItem(withTitle: "打开灵性日历", action: #selector(showMain), keyEquivalent: "")
        menu.addItem(withTitle: "和阿灵聊聊", action: #selector(openChat), keyEquivalent: "")
        menu.addItem(withTitle: "显示 / 隐藏桌面阿灵", action: #selector(togglePet), keyEquivalent: "")
        menu.addItem(.separator()); menu.addItem(withTitle: "偏好设置…", action: #selector(settings), keyEquivalent: "")
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        store.scheduleSystemReload()
        Task { await store.refreshNotifications(requestPermission: false) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
}

struct PetView: View {
    @ObservedObject var store: AppStore
    var open: () -> Void
    var body: some View {
        VStack(spacing: 2) {
            HStack { Spacer(); PetDragHandle().frame(width: 34, height: 15).overlay(Text("···").font(.system(size: 12)).foregroundStyle(Theme.secondary).allowsHitTesting(false)).help("拖动这里移动阿灵"); Spacer(); Button { store.togglePet() } label: { Image(systemName: "xmark").font(.system(size: 8)).padding(5).background(Theme.paper.opacity(0.9), in: Circle()) }.buttonStyle(.plain).help("隐藏阿灵，可从菜单栏重新显示") }.padding(.trailing, 12)
            SpiritView(size: 80).onTapGesture(perform: open).help("点击聊天 · 拖动空白处移动")
            Button("阿灵在这里") { open() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.jade).padding(.horizontal, 10).padding(.vertical, 5).background(Theme.paper, in: Capsule())
        }.frame(width: 116, height: 136).contentShape(Rectangle())
            .contextMenu { Button("打开日历") { store.showMainAction?() }; Button("聊一聊", action: open); Button("隐藏阿灵") { store.togglePet() } }
    }
}

struct PetDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
