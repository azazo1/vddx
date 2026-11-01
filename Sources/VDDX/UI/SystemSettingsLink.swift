import AppKit

/// 跳转到系统设置的相关面板.
enum SystemSettingsLink {
    case displays
    case screenRecording

    var url: URL {
        switch self {
        case .displays:
            return URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        }
    }

    func open() {
        Log.shared.info("打开系统设置面板: \(self)")
        NSWorkspace.shared.open(url)
    }
}
