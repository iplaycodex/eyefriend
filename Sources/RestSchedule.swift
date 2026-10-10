import Foundation

struct RestSchedule {
    enum Phase: Equatable { case paused, focusing, resting }
    private(set) var phase: Phase = .paused
    private(set) var deadline: Date?

    mutating func start(now: Date, minutes: Int) {
        phase = .focusing
        deadline = now.addingTimeInterval(Double(minutes * 60))
    }

    mutating func pause() {
        phase = .paused
        deadline = nil
    }

    mutating func rest(now: Date, seconds: Int) {
        phase = .resting
        deadline = now.addingTimeInterval(Double(seconds))
    }

    mutating func snooze(now: Date) {
        phase = .focusing
        deadline = now.addingTimeInterval(5 * 60)
    }

    func remaining(at now: Date) -> Int {
        guard let deadline else { return 0 }
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    mutating func tick(now: Date, minutes: Int, seconds: Int) {
        guard let deadline, now >= deadline else { return }
        switch phase {
        case .focusing: rest(now: now, seconds: seconds)
        case .resting: start(now: now, minutes: minutes)
        case .paused: break
        }
    }
}
