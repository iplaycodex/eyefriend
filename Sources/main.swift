import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    #if EYE_REST_TESTING
    let model = AppModel(preferences: nil)
    #else
    let model = AppModel(preferences: .standard)
    #endif
    let filters = ScreenFilters()
    private(set) var mainWindow: NSWindow!
    private(set) var restPanel: NSPanel!
    private(set) var statusItem: NSStatusItem!
    private var filterItem: NSMenuItem!
    private var reminderItem: NSMenuItem!
    private var lastFilterState = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        buildMenu()
        buildWindows()
        buildStatusItem()
        model.onChange = { [weak self] in self?.refresh() }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp),
            name: NSWorkspace.didWakeNotification, object: nil)
        model.startTimer()
        refresh()
        showMainWindow()
        #if EYE_REST_TESTING
        Task { await runSmokeTests(app: self) }
        #endif
    }

    private func buildWindows() {
        let content = NSHostingView(rootView: MainView(model: model))
        let size = content.fittingSize
        mainWindow = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        mainWindow.title = "留白"
        mainWindow.contentView = content
        mainWindow.setContentSize(size)
        mainWindow.isReleasedWhenClosed = false
        mainWindow.delegate = self
        mainWindow.center()

        let restContent = NSHostingView(rootView: RestView(model: model))
        restPanel = NSPanel(contentRect: NSRect(origin: .zero, size: restContent.fittingSize),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        restPanel.title = "休息一下"
        restPanel.contentView = restContent
        restPanel.isReleasedWhenClosed = false
        restPanel.isFloatingPanel = true
        restPanel.hidesOnDeactivate = false
        restPanel.level = .floating
        restPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        restPanel.delegate = self
        restPanel.center()
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func buildMenu() {
        let bar = NSMenu()
        let appMenu = NSMenu(title: "留白")
        appMenu.addItem(item("关于留白", #selector(about)))
        appMenu.addItem(.separator())
        let hide = NSMenuItem(title: "隐藏留白", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(hide)
        appMenu.addItem(.separator())
        appMenu.addItem(item("退出留白", #selector(quit), key: "q"))
        let root = NSMenuItem()
        root.submenu = appMenu
        bar.addItem(root)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(item("打开主窗口", #selector(showMainWindow), key: "0"))
        windowMenu.addItem(item("最小化", #selector(minimizeMainWindow), key: "m"))
        windowMenu.addItem(item("关闭窗口", #selector(closeMainWindow), key: "w"))
        let windowRoot = NSMenuItem()
        windowRoot.submenu = windowMenu
        bar.addItem(windowRoot)
        NSApp.mainMenu = bar
        NSApp.windowsMenu = windowMenu
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "eye", accessibilityDescription: "留白")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        let menu = NSMenu()
        menu.addItem(item("打开留白", #selector(showMainWindow)))
        menu.addItem(.separator())
        filterItem = item("开启屏幕滤镜", #selector(toggleFilter))
        reminderItem = item("开启休息提醒", #selector(toggleReminder))
        menu.addItem(filterItem)
        menu.addItem(reminderItem)
        menu.addItem(item("现在休息", #selector(restNow)))
        menu.addItem(.separator())
        menu.addItem(item("退出留白", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    func refresh() {
        let filterState = "\(model.filterEnabled)-\(model.warmth)-\(model.dimming)"
        if filterState != lastFilterState {
            filters.apply(enabled: model.filterEnabled, warmth: model.warmth, dimming: model.dimming)
            lastFilterState = filterState
        }
        filterItem.title = model.filterEnabled ? "关闭屏幕滤镜" : "开启屏幕滤镜"
        filterItem.state = model.filterEnabled ? .on : .off
        reminderItem.title = model.reminderEnabled ? "暂停休息提醒" : "开启休息提醒"
        reminderItem.state = model.reminderEnabled ? .on : .off
        statusItem.button?.toolTip = model.reminderEnabled
            ? "留白 · \(model.schedule.phase == .resting ? "休息剩余" : "下次休息") \(model.countdown)"
            : "留白 · 休息提醒未开启"
        if model.schedule.phase == .resting {
            if !restPanel.isVisible {
                restPanel.center()
                restPanel.orderFrontRegardless()
            }
        } else { restPanel.orderOut(nil) }
    }

    @objc func showMainWindow() {
        NSApp.unhide(nil)
        if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func minimizeMainWindow() { mainWindow.performMiniaturize(nil) }
    @objc func closeMainWindow() { mainWindow.performClose(nil) }
    @objc func toggleFilter() { model.filterEnabled.toggle() }
    @objc func toggleReminder() { model.reminderEnabled.toggle() }
    @objc func restNow() { model.restNow() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "留白", .applicationVersion: "0.1.0",
            .credits: NSAttributedString(string: "柔和屏幕，记得休息。\n为你的 Mac 制作。")
        ])
    }

    @objc private func screensChanged() {
        filters.remove()
        lastFilterState = ""
        refresh()
    }

    @objc private func wokeUp() {
        model.resetAfterWake()
        screensChanged()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === restPanel { model.snooze(); return false }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopTimer()
        filters.remove()
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
