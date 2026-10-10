import CoreGraphics
import Foundation

struct GammaTable: Equatable {
    var red: [Float]
    var green: [Float]
    var blue: [Float]

    var isValid: Bool {
        red.count >= 2 && red.count == green.count && red.count == blue.count &&
        [red, green, blue].allSatisfy { $0.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 } }
    }

    func scaled(by gain: RGBGain) -> GammaTable {
        GammaTable(red: red.map { $0 * Float(EyeComfort.clamp(gain.red)) },
                   green: green.map { $0 * Float(EyeComfort.clamp(gain.green)) },
                   blue: blue.map { $0 * Float(EyeComfort.clamp(gain.blue)) })
    }
}

struct GammaError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
protocol GammaBackend {
    func displays() throws -> [CGDirectDisplayID]
    func read(_ display: CGDirectDisplayID) throws -> GammaTable
    func write(_ table: GammaTable, to display: CGDirectDisplayID) throws
}

@MainActor
final class CoreGraphicsGamma: GammaBackend {
    func displays() throws -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        try check(CGGetActiveDisplayList(0, nil, &count), "读取显示器列表")
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        try check(CGGetActiveDisplayList(count, &ids, &count), "读取显示器列表")
        return Array(ids.prefix(Int(count)))
    }

    func read(_ display: CGDirectDisplayID) throws -> GammaTable {
        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity >= 2, capacity <= 65536 else {
            throw GammaError(message: "显示器 \(display) 不支持读取 Gamma 表。")
        }
        var red = [Float](repeating: 0, count: Int(capacity))
        var green = red, blue = red
        var count: UInt32 = 0
        try check(CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count),
                  "读取显示器 \(display) 的原始颜色")
        let table = GammaTable(red: Array(red.prefix(Int(count))),
                               green: Array(green.prefix(Int(count))), blue: Array(blue.prefix(Int(count))))
        guard count <= capacity, table.isValid else {
            throw GammaError(message: "显示器 \(display) 返回了无效的 Gamma 表。")
        }
        return table
    }

    func write(_ table: GammaTable, to display: CGDirectDisplayID) throws {
        guard table.isValid else { throw GammaError(message: "拒绝写入无效的 Gamma 表。") }
        try check(CGSetDisplayTransferByTable(display, UInt32(table.red.count),
                                             table.red, table.green, table.blue),
                  "调整显示器 \(display) 的颜色")
    }

    private func check(_ error: CGError, _ operation: String) throws {
        if error != .success { throw GammaError(message: "\(operation)失败（\(error.rawValue)）。") }
    }
}

@MainActor
final class ScreenGamma {
    let backend: any GammaBackend
    private(set) var originals: [CGDirectDisplayID: GammaTable] = [:]
    private var lastGains: [CGDirectDisplayID: RGBGain] = [:]
    private(set) var fault: String?

    init(backend: any GammaBackend = CoreGraphicsGamma()) { self.backend = backend }

    // Always derive from the captured baseline, never from an already dimmed table.
    @discardableResult
    func apply(enabled: Bool, gains: RGBGain) -> String? {
        guard enabled else { return restore() }
        guard fault == nil else { return fault }
        do {
            let displays = try backend.displays()
            guard !displays.isEmpty else { throw GammaError(message: "当前没有可调整的显示器。") }
            for display in displays {
                if originals[display] == nil { originals[display] = try backend.read(display) }
                guard lastGains[display] != gains, let baseline = originals[display] else { continue }
                try backend.write(baseline.scaled(by: gains), to: display)
                lastGains[display] = gains
            }
            return nil
        } catch {
            let failure = error.localizedDescription
            let recovery = restore()
            fault = failure + (recovery.map { " 恢复失败：\($0)" } ?? " 已恢复可连接屏幕，请关闭后重试。")
            return fault
        }
    }

    // Keep failed/disconnected snapshots so later retries can still restore them.
    @discardableResult
    func restore() -> String? {
        do {
            let connected = Set(try backend.displays())
            var errors: [String] = []
            for (display, baseline) in originals where connected.contains(display) {
                do {
                    try backend.write(baseline, to: display)
                    originals.removeValue(forKey: display)
                    lastGains.removeValue(forKey: display)
                } catch { errors.append(error.localizedDescription) }
            }
            fault = errors.isEmpty ? nil : errors.joined(separator: " ")
        } catch { fault = error.localizedDescription }
        return fault
    }

    func invalidate() {
        // Reapply after wake/reconfiguration even if the desired gains did not change.
        lastGains.removeAll()
    }
}
