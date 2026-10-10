import Foundation
import CoreGraphics

@MainActor
final class FakeGamma: GammaBackend {
    var ids: [UInt32] = [1, 2]
    var tables: [UInt32: GammaTable] = [1: baseline, 2: baseline]
    var failRead: UInt32?
    var failWrite: UInt32?
    var failOnce = false
    var failList = false
    var listReads = 0
    var tableOnWriteFailure: GammaTable?
    var failReadAfterWriteFailure = false
    var writes = 0
    static let baseline = GammaTable(red: [0, 0.23, 0.75, 1],
                                     green: [0, 0.31, 0.8, 1], blue: [0, 0.2, 0.7, 1])
    func displays() throws -> [UInt32] {
        listReads += 1
        if failList { throw GammaError(message: "simulated display list failure") }
        return ids
    }
    func read(_ display: UInt32) throws -> GammaTable {
        if failRead == display { throw GammaError(message: "simulated read failure") }
        return tables[display]!
    }
    func write(_ table: GammaTable, to display: UInt32) throws {
        if failWrite == display {
            if let tableOnWriteFailure { tables[display] = tableOnWriteFailure }
            if failReadAfterWriteFailure { failRead = display }
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
    check((0..<1440).allSatisfy {
        let h = Double($0) / 60
        return (0.0999...0.9001).contains(EyeComfort.smartLevel(hour: h))
    }, "all 1440 minutes remain in curve bounds")
    check([3.0, 7, 12, 18].allSatisfy {
        abs(EyeComfort.smartLevel(hour: $0 - 0.00001) - EyeComfort.smartLevel(hour: $0)) < 0.00001
    }, "smart segment boundaries are continuous")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 16, minute: 30))!
    check(near(EyeComfort.hour(at: date, calendar: calendar), 16.5), "local time uses minutes / 60")
    let gain = EyeComfort.gains(level: 0.9)
    check(near(gain.red, 0.91) && near(gain.green, 0.775) && near(gain.blue, 0.55), "original RGB attenuation coefficients")
    let lowerGain = EyeComfort.gains(level: 0.1)
    check(near(lowerGain.red, 0.99) && near(lowerGain.green, 0.975) && near(lowerGain.blue, 0.95),
          "no additional dimming or night green coefficient")
    check(EyeComfort.gains(level: .nan) == .identity, "nonfinite strength resolves to identity")

    let model = AppModel(preferences: nil)
    let local = Calendar.current
    let noon = local.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
    let midnight = local.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 0))!
    model.smartEnabled = true
    model.tick(at: noon)
    check(near(model.effectiveLevel, 0.1), "automatic mode follows injected noon time")
    model.tick(at: midnight)
    check(near(model.effectiveLevel, 0.75), "automatic mode changes across midnight")
    model.smartEnabled = false
    model.tick(at: noon)
    check(!model.smartEnabled, "timer does not re-enable disabled protection")

    func restoredModel(_ values: [String: Any]) -> AppModel {
        let suite = "local.eyerest.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
        defer { defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain) }
        return AppModel(preferences: defaults)
    }
    check(!restoredModel([:]).smartEnabled, "fresh install stays disabled")
    check(restoredModel(["filterEnabled": true, "smartEnabled": true]).smartEnabled,
          "upgrade preserves active automatic protection")
    check(!restoredModel(["filterEnabled": false, "smartEnabled": true]).smartEnabled,
          "upgrade preserves disabled master switch")
    check(!restoredModel(["filterEnabled": true, "smartEnabled": false]).smartEnabled,
          "removed manual mode does not silently enable automatic protection")
    check(restoredModel(["intelligentEnabled": true, "filterEnabled": false]).smartEnabled,
          "new single-switch preference overrides legacy master")
    check(!restoredModel(["intelligentEnabled": false, "filterEnabled": true, "smartEnabled": true]).smartEnabled,
          "new disabled preference overrides old switches")
    let legacy = restoredModel(["filterEnabled": true, "smartEnabled": true, "nightEnabled": true,
                                "dimming": 1.0, "warmth": 1.0, "reminderEnabled": true])
    legacy.tick(at: midnight)
    let midnightGain = EyeComfort.gains(level: 0.75)
    check(legacy.gammaGains == midnightGain, "removed settings cannot affect automatic Gamma")

    let backend = FakeGamma()
    let gamma = ScreenGamma(backend: backend)
    check(gamma.apply(enabled: true, gains: gain) == nil && gamma.originals.count == 2,
          "capture both displays before adjusting")
    let applied = backend.tables
    _ = gamma.apply(enabled: true, gains: gain)
    check(backend.tables == applied && backend.writes == 2, "unchanged gain does not accumulate or rewrite")
    _ = gamma.apply(enabled: true, gains: lowerGain)
    check(backend.tables[1] == FakeGamma.baseline.scaled(by: lowerGain), "changed gain derives from original calibration")
    gamma.invalidate()
    backend.tables[1] = FakeGamma.baseline
    _ = gamma.apply(enabled: true, gains: lowerGain)
    check(backend.tables[1] == FakeGamma.baseline.scaled(by: lowerGain), "wake/reconfiguration reapplies same gains")
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

    let rejecting = FakeGamma()
    rejecting.failWrite = 2
    let rejectingGamma = ScreenGamma(backend: rejecting)
    check(rejectingGamma.apply(enabled: true, gains: gain) != nil,
          "permanent rejection still reports apply failure")
    check(rejecting.tables.values.allSatisfy { $0 == FakeGamma.baseline },
          "permanent rejection rolls back the other display")
    check(rejectingGamma.originals.isEmpty,
          "confirmed unchanged rejected display releases snapshot")
    check(rejectingGamma.apply(enabled: false, gains: gain) == nil && rejectingGamma.fault == nil,
          "disable succeeds after confirmed unchanged rejection")
    check(rejectingGamma.restore() == nil, "quit restoration succeeds after permanent rejection")
    rejecting.failWrite = nil
    check(rejectingGamma.apply(enabled: true, gains: gain) == nil && rejectingGamma.originals.count == 2,
          "re-enable captures both displays after rejection recovery")
    _ = rejectingGamma.restore()

    let unknown = FakeGamma()
    unknown.failWrite = 2
    unknown.failReadAfterWriteFailure = true
    let unknownGamma = ScreenGamma(backend: unknown)
    _ = unknownGamma.apply(enabled: true, gains: gain)
    check(unknownGamma.originals[2] != nil && unknownGamma.restore() != nil,
          "failed readback retains unknown snapshot and blocks exit")
    unknown.failRead = nil
    unknown.failWrite = nil
    check(unknownGamma.restore() == nil && unknownGamma.originals.isEmpty,
          "unknown snapshot can be restored on retry")

    let partial = FakeGamma()
    partial.failWrite = 2
    partial.tableOnWriteFailure = FakeGamma.baseline.scaled(by: gain)
    let partialGamma = ScreenGamma(backend: partial)
    _ = partialGamma.apply(enabled: true, gains: gain)
    check(partialGamma.originals[2] != nil && partialGamma.restore() != nil,
          "partial mutation despite write failure retains snapshot and blocks exit")
    partial.failWrite = nil
    check(partialGamma.restore() == nil && partial.tables[2] == FakeGamma.baseline,
          "partial mutation restores baseline on retry")

    let empty = FakeGamma()
    empty.failList = true
    let emptyGamma = ScreenGamma(backend: empty)
    check(emptyGamma.restore() == nil && empty.listReads == 0,
          "never-enabled quit avoids display enumeration")
    _ = emptyGamma.apply(enabled: true, gains: gain)
    let listReads = empty.listReads
    check(emptyGamma.apply(enabled: false, gains: gain) == nil && emptyGamma.fault == nil &&
          empty.listReads == listReads, "empty restore clears prior fault without enumeration")

    let pending = FakeGamma()
    let pendingGamma = ScreenGamma(backend: pending)
    _ = pendingGamma.apply(enabled: true, gains: gain)
    pending.failList = true
    check(pendingGamma.restore() != nil && pendingGamma.originals.count == 2,
          "enumeration failure with modified displays still blocks exit")
    pending.failList = false
    check(pendingGamma.restore() == nil && pendingGamma.originals.isEmpty,
          "pending snapshots restore after enumeration recovers")

}

func tablesClose(_ a: GammaTable, _ b: GammaTable, tolerance: Float = 0.005) -> Bool {
    guard a.red.count == b.red.count, a.green.count == b.green.count, a.blue.count == b.blue.count else { return false }
    return zip(a.red + a.green + a.blue, b.red + b.green + b.blue).allSatisfy { abs($0 - $1) <= tolerance }
}
