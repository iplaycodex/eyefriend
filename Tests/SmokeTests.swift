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

    runGammaTests(check: check)

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

    check(app.statusItem.menu?.items.filter { !$0.isSeparatorItem }.map(\.title) ==
          ["打开留白", "开启智能护眼", "退出留白"], "menu exposes only automatic protection")

    let backend = CoreGraphicsGamma()
    var before: [UInt32: GammaTable] = [:]
    do {
        for display in try backend.displays() { before[display] = try backend.read(display) }
        check(!before.isEmpty, "read actual display gamma baseline")
        app.model.smartEnabled = true
        check(app.model.gammaError == nil && app.gamma.originals.count == before.count,
              "Gamma applied to connected displays")
        for (display, baseline) in before {
            let actual = try backend.read(display)
            check(tablesClose(actual, baseline.scaled(by: app.model.gammaGains)),
                  "display \(display) actual Gamma readback matches target")
            check(!tablesClose(actual, baseline), "display \(display) actually changes")
        }
        let lateNight = EyeComfort.gains(level: 0.75)
        check(app.gamma.apply(enabled: true, gains: lateNight) == nil, "apply midnight Gamma without changing system clock")
        for (display, baseline) in before {
            check(tablesClose(try backend.read(display), baseline.scaled(by: lateNight)),
                  "display \(display) midnight automatic curve readback")
        }
        app.willSleep()
        for (display, baseline) in before {
            check(tablesClose(try backend.read(display), baseline), "sleep restores display \(display)")
        }
        app.wokeUp()
        check(app.gamma.originals.count == before.count, "wake reapplies screen adjustments")
        app.model.smartEnabled = false
        for (display, baseline) in before {
            check(tablesClose(try backend.read(display), baseline), "disable restores display \(display)")
        }
        check(app.gamma.originals.isEmpty, "successful restore releases snapshots")
    } catch {
        check(false, "real Gamma verification: \(error.localizedDescription)")
        _ = app.gamma.restore()
    }
    app.model.smartEnabled = true
    app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    check(app.gamma.originals.isEmpty, "quit cleanup restores Gamma")
    for (display, baseline) in before {
        do { check(tablesClose(try backend.read(display), baseline), "quit restores display \(display) readback") }
        catch { check(false, "quit readback failed: \(error)") }
    }

    print("RESULT: \(checks - failures.count)/\(checks) passed")
    if !failures.isEmpty { print(failures.joined(separator: "\n")) }
    fflush(stdout)
    exit(failures.isEmpty ? 0 : 1)
}
