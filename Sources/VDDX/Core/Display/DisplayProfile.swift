import Foundation

/// 一块虚拟屏的配置.
struct DisplayProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// 逻辑分辨率, 即系统里该屏的"看起来"尺寸.
    var logicalWidth: Int
    var logicalHeight: Int
    var refreshRate: Double
    var hiDPI: Bool
    /// 应用启动时自动重建这块屏.
    var autoRestore: Bool

    /// 实际像素尺寸, HiDPI 时为逻辑尺寸的两倍.
    var pixelWidth: Int { hiDPI ? logicalWidth * 2 : logicalWidth }
    var pixelHeight: Int { hiDPI ? logicalHeight * 2 : logicalHeight }

    var resolutionLabel: String { "\(logicalWidth) x \(logicalHeight)" }

    var refreshRateLabel: String {
        refreshRate.rounded() == refreshRate
            ? "\(Int(refreshRate)) Hz"
            : String(format: "%.2f Hz", refreshRate)
    }

    var detailLabel: String {
        var parts = [resolutionLabel, refreshRateLabel]
        if hiDPI { parts.append("HiDPI") }
        if autoRestore { parts.append("启动时重建") }
        return parts.joined(separator: "  ·  ")
    }

    /// 用于界面展示的宽高比, 例如 `16:9`.
    var aspectRatioLabel: String {
        let divisor = Self.greatestCommonDivisor(logicalWidth, logicalHeight)
        guard divisor > 0 else { return "\(logicalWidth):\(logicalHeight)" }
        return "\(logicalWidth / divisor):\(logicalHeight / divisor)"
    }

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard logicalWidth >= 640, logicalWidth <= 7680 else { return false }
        guard logicalHeight >= 480, logicalHeight <= 4320 else { return false }
        guard refreshRate >= 24, refreshRate <= 240 else { return false }
        return true
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = abs(lhs)
        var b = abs(rhs)
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return a
    }
}
