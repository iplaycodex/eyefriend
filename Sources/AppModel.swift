import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var filterEnabled = false { didSet { update() } }
    @Published var warmth = 0.28 { didSet { update() } }
    @Published var dimming = 0.10 { didSet { update() } }
    @Published var reminderEnabled = false {
        didSet {
            if reminderEnabled { schedule.start(now: Date(), minutes: interval) }
            else { schedule.pause() }
            update()
        }
    }
    @Published var interval = 20 {
        didSet {
            if reminderEnabled { schedule.start(now: Date(), minutes: interval) }
            update()
        }
    }
    @Published var duration = 20 {
        didSet {
            if schedule.phase == .resting { schedule.rest(now: Date(), seconds: duration) }
            update()
        }
    }
    @Published private(set) var schedule = RestSchedule()
    @Published private(set) var now = Date()
    var onChange: (() -> Void)?
    private var timer: Timer?
    private let preferences: UserDefaults?

    init(preferences: UserDefaults?) {
        self.preferences = preferences
        if let preferences {
            filterEnabled = preferences.bool(forKey: "filterEnabled")
            warmth = Self.clamp(preferences.object(forKey: "warmth") as? Double ?? 0.28)
            dimming = Self.clamp(preferences.object(forKey: "dimming") as? Double ?? 0.10)
            let savedInterval = preferences.integer(forKey: "interval")
            interval = [20, 30, 45, 60].contains(savedInterval) ? savedInterval : 20
            let savedDuration = preferences.integer(forKey: "duration")
            duration = [20, 30, 60].contains(savedDuration) ? savedDuration : 20
            reminderEnabled = preferences.bool(forKey: "reminderEnabled")
        }
        if reminderEnabled { schedule.start(now: Date(), minutes: interval) }
    }

    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    var countdown: String {
        let remaining = schedule.remaining(at: now)
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func tick() {
        now = Date()
        schedule.tick(now: now, minutes: interval, seconds: duration)
        onChange?()
    }

    func restNow() {
        if !reminderEnabled { reminderEnabled = true }
        now = Date()
        schedule.rest(now: now, seconds: duration)
        onChange?()
    }

    func snooze() {
        now = Date()
        if reminderEnabled { schedule.snooze(now: now) }
        else { schedule.pause() }
        onChange?()
    }

    func finishRest() {
        now = Date()
        if reminderEnabled { schedule.start(now: now, minutes: interval) }
        else { schedule.pause() }
        onChange?()
    }

    func resetAfterWake() {
        now = Date()
        if reminderEnabled { schedule.start(now: now, minutes: interval) }
        onChange?()
    }

    private func update() {
        now = Date()
        if let preferences {
            preferences.set(filterEnabled, forKey: "filterEnabled")
            preferences.set(warmth, forKey: "warmth")
            preferences.set(dimming, forKey: "dimming")
            preferences.set(reminderEnabled, forKey: "reminderEnabled")
            preferences.set(interval, forKey: "interval")
            preferences.set(duration, forKey: "duration")
        }
        onChange?()
    }
}

final class FilterWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ScreenFilters {
    private(set) var windows: [FilterWindow] = []

    func apply(enabled: Bool, warmth: Double, dimming: Double) {
        guard enabled else { remove(); return }
        if windows.count != NSScreen.screens.count { rebuild() }
        let warmAlpha = AppModel.clamp(warmth) * 0.30
        let darkAlpha = AppModel.clamp(dimming) * 0.50
        // Compose amber over black, keeping a bounded, reversible opacity.
        let alpha = warmAlpha + darkAlpha * (1 - warmAlpha)
        let factor = alpha > 0 ? warmAlpha / alpha : 0
        let color = NSColor(srgbRed: factor, green: 0.65 * factor,
                            blue: 0.22 * factor, alpha: alpha)
        for (window, screen) in zip(windows, NSScreen.screens) {
            window.setFrame(screen.frame, display: true)
            window.backgroundColor = color
            window.orderFrontRegardless()
        }
    }

    func rebuild() {
        remove()
        windows = NSScreen.screens.map { screen in
            let window = FilterWindow(contentRect: screen.frame, styleMask: .borderless,
                                      backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isExcludedFromWindowsMenu = true
            return window
        }
    }

    func remove() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }
}
