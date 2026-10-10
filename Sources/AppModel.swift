import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var smartEnabled = false { didSet { update() } }
    @Published var gammaError: String?
    @Published private(set) var now = Date()
    var onChange: (() -> Void)?
    private var timer: Timer?
    private let preferences: UserDefaults?

    init(preferences: UserDefaults?) {
        self.preferences = preferences
        if let preferences {
            if preferences.object(forKey: "intelligentEnabled") != nil {
                smartEnabled = preferences.bool(forKey: "intelligentEnabled")
            } else {
                // Preserve the actual on/off state when upgrading from the two-switch UI.
                smartEnabled = preferences.bool(forKey: "filterEnabled") &&
                               preferences.bool(forKey: "smartEnabled")
            }
        }
    }

    var effectiveLevel: Double {
        EyeComfort.smartLevel(hour: EyeComfort.hour(at: now))
    }

    var gammaGains: RGBGain { EyeComfort.gains(level: effectiveLevel) }

    func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
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
        onChange?()
    }

    private func update() {
        preferences?.set(smartEnabled, forKey: "intelligentEnabled")
        tick()
    }
}
