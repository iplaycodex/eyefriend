import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    #if EYE_REST_TESTING
    let model = AppModel(preferences: nil)
    #else
    let model = AppModel(preferences: .standard)
    #endif
    let gamma = ScreenGamma()
    private var sleeping = false
    private(set) var mainWindow: NSWindow!
    private(set) var statusItem: NSStatusItem!
    private var smartItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        #if !EYE_REST_TESTING
        NSApp.applicationIconImage = Artwork.image("AppIcon", extension: "icns")
        #endif
        buildMenu()
        buildWindows()
        buildStatusItem()
        model.onChange = { [weak self] in self?.refresh() }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp),
            name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
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
        mainWindow.title = "EyeFriend"
        mainWindow.contentView = content
        mainWindow.setContentSize(size)
        mainWindow.isReleasedWhenClosed = false
        mainWindow.center()
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func buildMenu() {
        let bar = NSMenu()
        let appMenu = NSMenu(title: "EyeFriend")
        appMenu.addItem(item("关于EyeFriend", #selector(about)))
        appMenu.addItem(.separator())
        let hide = NSMenuItem(title: "隐藏EyeFriend", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(hide)
        appMenu.addItem(.separator())
        appMenu.addItem(item("退出EyeFriend", #selector(quit), key: "q"))
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
        let icon = Artwork.image("StatusBar_Icon")
        icon.size = NSSize(width: 22, height: 22)
        icon.isTemplate = true
        statusItem.button?.image = icon
        let highlightedIcon = Artwork.image("StatusBar_Icon_Highlight")
        highlightedIcon.size = NSSize(width: 22, height: 22)
        highlightedIcon.isTemplate = true
        statusItem.button?.alternateImage = highlightedIcon
        statusItem.button?.setAccessibilityLabel("EyeFriend")
        let menu = NSMenu()
        menu.addItem(item("打开EyeFriend", #selector(showMainWindow)))
        menu.addItem(.separator())
        smartItem = item("开启智能护眼", #selector(toggleSmart))
        menu.addItem(smartItem)
        menu.addItem(.separator())
        menu.addItem(item("退出EyeFriend", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    func refresh() {
        let error = gamma.apply(enabled: model.smartEnabled && !sleeping, gains: model.gammaGains)
        if model.gammaError != error { model.gammaError = error }
        smartItem.title = model.smartEnabled ? "关闭智能护眼" : "开启智能护眼"
        smartItem.state = model.smartEnabled ? .on : .off
        statusItem.button?.toolTip = model.gammaError.map { "EyeFriend · " + $0 } ??
            (model.smartEnabled ? "EyeFriend · 智能护眼 \(Int((model.effectiveLevel * 100).rounded()))%" : "EyeFriend · 智能护眼已关闭")
    }

    @objc func showMainWindow() {
        NSApp.unhide(nil)
        if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func minimizeMainWindow() { mainWindow.performMiniaturize(nil) }
    @objc func closeMainWindow() { mainWindow.performClose(nil) }
    @objc func toggleSmart() { model.smartEnabled.toggle() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "EyeFriend", .applicationVersion: "0.3.2",
            .credits: NSAttributedString(string: "跟随时间，自动调节屏幕。\n为你的 Mac 制作。")
        ])
    }

    @objc private func screensChanged() {
        gamma.invalidate()
        refresh()
    }

    @objc func willSleep() {
        sleeping = true
        refresh()
    }

    @objc func wokeUp() {
        sleeping = false
        gamma.invalidate()
        model.tick()
        screensChanged()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let error = gamma.restore() {
            model.gammaError = error
            showMainWindow()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopTimer()
        _ = gamma.restore()
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
