import Foundation
import CoreGraphics

@MainActor
final class FakeGamma: GammaBackend {
    var ids: [UInt32] = [1, 2]
    var tables: [UInt32: GammaTable] = [1: baseline, 2: baseline]
    var failRead: UInt32?
    var failWrite: UInt32?
    var failOnce = false
    var writes = 0
    static let baseline = GammaTable(red: [0, 0.23, 0.75, 1],
                                     green: [0, 0.31, 0.8, 1], blue: [0, 0.2, 0.7, 1])
    func displays() throws -> [UInt32] { ids }
    func read(_ display: UInt32) throws -> GammaTable {
        if failRead == display { throw GammaError(message: "simulated read failure") }
        return tables[display]!
    }
    func write(_ table: GammaTable, to display: UInt32) throws {
        if failWrite == display {
            if failOnce { failWrite = nil }
            throw GammaError(message: "simulated write failure")
        }
        writes += 1
        tables[display] = table
    }
}

@MainActor
func runGammaTests(check: (Bool, String) -> Void) {
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000001 }
    for (hour, level) in [(0.0, 0.75), (3, 0.9), (7, 0.3), (12, 0.1), (18, 0.3), (24, 0.75), (16.5, 0.25)] {
        check(near(EyeComfort.smartLevel(hour: hour), level), "smart curve at \(hour): \(level)")
    }
    for (hour, gain) in [(0.0, 0.8), (4, 0.8), (6, 0.9), (8, 1), (12, 1), (20, 1), (22, 0.9), (24, 0.8)] {
        check(near(EyeComfort.nightGreen(hour: hour), gain), "night curve at \(hour): \(gain)")
    }
    check((0..<1440).allSatisfy {
        let h = Double($0) / 60
        return (0.0999...0.9001).contains(EyeComfort.smartLevel(hour: h)) &&
               (0.7999...1.0001).contains(EyeComfort.nightGreen(hour: h))
    }, "all 1440 minutes remain in curve bounds")
    check([3.0, 7, 12, 18].allSatisfy {
        abs(EyeComfort.smartLevel(hour: $0 - 0.00001) - EyeComfort.smartLevel(hour: $0)) < 0.00001
    }, "smart segment boundaries are continuous")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 16, minute: 30))!
    check(near(EyeComfort.hour(at: date, calendar: calendar), 16.5), "local time uses minutes / 60")
    let gain = EyeComfort.gains(level: 0.9, dimming: 0, night: false, hour: 3)
    check(near(gain.red, 0.91) && near(gain.green, 0.775) && near(gain.blue, 0.55), "original RGB attenuation coefficients")
    let night = EyeComfort.gains(level: 0.9, dimming: 1, night: true, hour: 3)
    check(near(night.red, 0.455) && near(night.green, 0.31) && near(night.blue, 0.275),
          "night green gain and dimming compose independently")
    check(EyeComfort.gains(level: .nan, dimming: .infinity, night: true, hour: .nan) == .identity,
          "nonfinite inputs safely resolve to identity")

    let model = AppModel(preferences: nil)
    let local = Calendar.current
    let noon = local.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
    let midnight = local.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 0))!
    model.warmth = 0.42
    model.smartEnabled = true
    model.tick(at: noon)
    check(near(model.effectiveLevel, 0.1), "automatic mode follows injected noon time")
    model.tick(at: midnight)
    check(near(model.effectiveLevel, 0.75), "automatic mode changes across midnight")
    model.smartEnabled = false
    model.tick(at: noon)
    check(near(model.effectiveLevel, 0.42), "leaving automatic mode restores manual setting")
    model.nightEnabled = true
    model.tick(at: midnight)
    check(near(model.gammaGains.green, (1 - 0.25 * 0.42) * 0.95 * 0.8),
          "night mode applies even with manual warmth")
    model.tick(at: noon)
    check(near(model.gammaGains.green, (1 - 0.25 * 0.42) * 0.95), "night mode recovers during daytime")

    let backend = FakeGamma()
    let gamma = ScreenGamma(backend: backend)
    check(gamma.apply(enabled: true, gains: gain) == nil && gamma.originals.count == 2,
          "capture both displays before adjusting")
    let applied = backend.tables
    _ = gamma.apply(enabled: true, gains: gain)
    check(backend.tables == applied && backend.writes == 2, "unchanged gain does not accumulate or rewrite")
    _ = gamma.apply(enabled: true, gains: night)
    check(backend.tables[1] == FakeGamma.baseline.scaled(by: night), "changed gain derives from original calibration")
    gamma.invalidate()
    backend.tables[1] = FakeGamma.baseline
    _ = gamma.apply(enabled: true, gains: night)
    check(backend.tables[1] == FakeGamma.baseline.scaled(by: night), "wake/reconfiguration reapplies same gains")
    backend.ids = [2]
    _ = gamma.restore()
    check(gamma.originals[1] != nil && backend.tables[2] == FakeGamma.baseline,
          "disconnect keeps original for later restoration")
    backend.ids = [1, 2]
    _ = gamma.restore()
    check(gamma.originals.isEmpty && backend.tables[1] == FakeGamma.baseline, "reconnected display restores")
    backend.failRead = 2
    check(gamma.apply(enabled: true, gains: gain) != nil && backend.tables[1] == FakeGamma.baseline,
          "second display read failure rolls back first display")
    backend.failRead = nil
    _ = gamma.restore()
    backend.failWrite = 2
    backend.failOnce = true
    check(gamma.apply(enabled: true, gains: gain) != nil && backend.tables[1] == FakeGamma.baseline &&
          backend.tables[2] == FakeGamma.baseline, "partial write failure rolls back all connected displays")
    _ = gamma.restore()
    _ = gamma.apply(enabled: true, gains: gain)
    backend.failWrite = 1
    backend.failOnce = false
    check(gamma.restore() != nil && gamma.originals[1] != nil, "failed restore retains original and reports error")
    backend.failWrite = nil
    check(gamma.restore() == nil && gamma.originals.isEmpty && backend.tables[1] == FakeGamma.baseline,
          "retry completes previously failed restore")
}

func tablesClose(_ a: GammaTable, _ b: GammaTable, tolerance: Float = 0.005) -> Bool {
    guard a.red.count == b.red.count, a.green.count == b.green.count, a.blue.count == b.blue.count else { return false }
    return zip(a.red + a.green + a.blue, b.red + b.green + b.blue).allSatisfy { abs($0 - $1) <= tolerance }
}
