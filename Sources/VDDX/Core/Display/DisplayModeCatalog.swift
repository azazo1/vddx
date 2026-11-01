import Foundation

/// 创建虚拟屏时可选的常用分辨率与刷新率.
enum DisplayModeCatalog {
    struct Preset: Identifiable, Hashable {
        let width: Int
        let height: Int

        var id: String { "\(width)x\(height)" }
        var label: String { "\(width) x \(height)" }
    }

    static let resolutionPresets: [Preset] = [
        Preset(width: 3840, height: 2160),
        Preset(width: 2560, height: 1440),
        Preset(width: 2560, height: 1600),
        Preset(width: 1920, height: 1080),
        Preset(width: 1920, height: 1200),
        Preset(width: 1680, height: 1050),
        Preset(width: 1600, height: 900),
        Preset(width: 1440, height: 900),
        Preset(width: 1280, height: 800),
        Preset(width: 1280, height: 720),
        Preset(width: 1024, height: 768)
    ]

    static let refreshRates: [Double] = [30, 50, 60, 75, 90, 120, 144]

    /// 用于物理尺寸换算的像素密度, 仅影响系统报告的物理大小.
    static let pixelsPerInch: Double = 110

    static func millimeters(forLogicalWidth width: Int, height: Int) -> (width: Double, height: Double) {
        let millimetersPerPixel = 25.4 / pixelsPerInch
        return (Double(width) * millimetersPerPixel, Double(height) * millimetersPerPixel)
    }
}
