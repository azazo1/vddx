import AppKit
import Foundation

/// 主窗口尺寸记忆.
///
/// 只记录非全屏下的尺寸, 不记录位置, 避免显示器变化后窗口落在屏幕外.
@MainActor
enum WindowStateStore {
    private struct State: Codable {
        var width: Double
        var height: Double
    }

    private static var url: URL {
        AppPaths.dataDirectory.appendingPathComponent("window.json")
    }

    static func loadSize() -> NSSize? {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(State.self, from: data),
              state.width > 0, state.height > 0 else {
            return nil
        }
        return NSSize(width: state.width, height: state.height)
    }

    static func saveSize(_ size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        let state = State(width: Double(size.width), height: Double(size.height))
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 把保存的尺寸夹取到当前主屏可用区域内.
    static func clamp(_ size: NSSize) -> NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let maxWidth = max(visible.width - 80, 640)
        let maxHeight = max(visible.height - 80, 480)
        return NSSize(
            width: min(max(size.width, 720), maxWidth),
            height: min(max(size.height, 480), maxHeight)
        )
    }
}
