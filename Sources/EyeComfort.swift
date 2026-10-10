import Foundation

struct RGBGain: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    static let identity = RGBGain(red: 1, green: 1, blue: 1)
}

enum EyeComfort {
    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    static func hour(at date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    // Reconstructed time curves; t is local decimal hours, not HH.mm.
    static func smartLevel(hour t: Double) -> Double {
        guard t.isFinite, t >= 0, t <= 24 else { return 0 }
        if t < 3 { return 0.75 + t * 0.05 }
        if t < 7 { return 0.9 - (t - 3) * 0.15 }
        if t < 12 { return 0.3 - (t - 7) * 0.04 }
        if t < 18 { return 0.1 + (t - 12) / 30 }
        return 0.3 + (t - 18) * 0.075
    }

    static func gains(level: Double) -> RGBGain {
        let strength = clamp(level)
        return RGBGain(red: 1 - 0.1 * strength,
                       green: 1 - 0.25 * strength,
                       blue: 1 - 0.5 * strength)
    }
}
