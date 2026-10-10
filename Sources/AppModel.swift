import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var smartEnabled = false { didSet { update() } }
    @Published var nightEnabled = false { didSet { update() } }
    @Published var gammaError: String?
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
            smartEnabled = preferences.bool(forKey: "smartEnabled")
            nightEnabled = preferences.bool(forKey: "nightEnabled")
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
        EyeComfort.clamp(value)
    }

    var effectiveLevel: Double {
        smartEnabled ? EyeComfort.smartLevel(hour: EyeComfort.hour(at: now)) : warmth
    }

    var gammaGains: RGBGain {
        EyeComfort.gains(level: effectiveLevel, dimming: dimming, night: nightEnabled,
                         hour: EyeComfort.hour(at: now))
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

    func tick(at date: Date = Date()) {
        now = date
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
            preferences.set(smartEnabled, forKey: "smartEnabled")
            preferences.set(nightEnabled, forKey: "nightEnabled")
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
