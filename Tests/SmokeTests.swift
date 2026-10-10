import AppKit

@MainActor
func runSmokeTests(app: AppDelegate) async {
    var failures: [String] = []
    var checks = 0
    func check(_ condition: Bool, _ label: String) {
        checks += 1
        if !condition { failures.append(label) }
        print("\(condition ? "PASS" : "FAIL") \(label)")
    }
    func settle() async { try? await Task.sleep(for: .seconds(0.8)) }

    let now = Date(timeIntervalSince1970: 1000)
    var schedule = RestSchedule()
    check(schedule.phase == .paused && schedule.deadline == nil, "reminder initially paused")
    schedule.start(now: now, minutes: 20)
    check(schedule.remaining(at: now) == 1200, "20 minute interval")
    schedule.tick(now: now.addingTimeInterval(1199), minutes: 20, seconds: 20)
    check(schedule.phase == .focusing, "no early reminder")
    schedule.tick(now: now.addingTimeInterval(1200), minutes: 20, seconds: 20)
    check(schedule.phase == .resting, "reminder begins at deadline")
    schedule.tick(now: now.addingTimeInterval(1220), minutes: 20, seconds: 20)
    check(schedule.phase == .focusing && schedule.remaining(at: now.addingTimeInterval(1220)) == 1200,
          "rest completes and resets interval")
    schedule.snooze(now: now)
    check(schedule.remaining(at: now) == 300, "snooze lasts 5 minutes")
    schedule.pause()
    schedule.tick(now: now.addingTimeInterval(9999), minutes: 20, seconds: 20)
    check(schedule.phase == .paused && schedule.deadline == nil, "pause cancels deadline")
    check(AppModel.clamp(.nan) == 0 && AppModel.clamp(2) == 1 && AppModel.clamp(-1) == 0,
          "invalid filter values remain bounded")

    await settle()
    check(app.mainWindow.isVisible, "main window shown")
    check(app.mainWindow.styleMask.contains(.miniaturizable), "native minimizable window style")
    check(app.mainWindow.standardWindowButton(.miniaturizeButton)?.isEnabled == true, "yellow button enabled")
    app.mainWindow.standardWindowButton(.miniaturizeButton)?.performClick(nil)
    await settle()
    check(app.mainWindow.isMiniaturized, "yellow button actually minimizes")
    app.showMainWindow()
    await settle()
    check(!app.mainWindow.isMiniaturized && app.mainWindow.isVisible, "restore after yellow button")
    let commandM = NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: .command, timestamp: 0, windowNumber: app.mainWindow.windowNumber,
        context: nil, characters: "m", charactersIgnoringModifiers: "m", isARepeat: false, keyCode: 46)!
    check(NSApp.mainMenu?.performKeyEquivalent(with: commandM) == true, "Command-M menu binding")
    await settle()
    check(app.mainWindow.isMiniaturized, "Command-M actually minimizes")

    app.model.restNow()
    check(app.restPanel.isVisible, "rest reminder appears while main window minimized")
    check(app.mainWindow.isMiniaturized, "rest reminder preserves minimization")
    app.restPanel.performClose(nil)
    check(!app.restPanel.isVisible && app.model.schedule.phase == .focusing,
          "closing reminder snoozes without quitting")
    check(app.model.schedule.remaining(at: Date()) <= 300, "reminder close sets snooze deadline")
    app.showMainWindow()
    await settle()
    app.closeMainWindow()
    check(!app.mainWindow.isVisible, "red close button hides main window")
    check(app.applicationShouldTerminateAfterLastWindowClosed(NSApp) == false,
          "closing main window keeps app alive")
    check(app.statusItem.isVisible && app.statusItem.menu != nil, "menu bar remains available")
    app.statusItem.menu?.performActionForItem(at: 0)
    await settle()
    check(app.mainWindow.isVisible, "menu bar reopens closed window")

    app.model.filterEnabled = true
    check(!NSScreen.screens.isEmpty && app.filters.windows.count == NSScreen.screens.count,
          "one filter per connected screen")
    check(app.filters.windows.allSatisfy { $0.ignoresMouseEvents && !$0.canBecomeKey && $0.isVisible },
          "filters are visible and do not intercept input")
    app.model.filterEnabled = false
    check(app.filters.windows.isEmpty, "disabling filter removes windows")
    app.model.restNow()
    app.model.resetAfterWake()
    check(app.model.schedule.phase == .focusing && !app.restPanel.isVisible,
          "wake resets timer and dismisses stale rest")
    app.model.reminderEnabled = false
    check(app.model.schedule.phase == .paused && !app.restPanel.isVisible,
          "disabling reminders clears rest state")
    app.model.filterEnabled = true
    app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    check(app.filters.windows.isEmpty, "quit cleanup removes filters")

    print("RESULT: \(checks - failures.count)/\(checks) passed")
    if !failures.isEmpty { print(failures.joined(separator: "\n")) }
    fflush(stdout)
    exit(failures.isEmpty ? 0 : 1)
}
