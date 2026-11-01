import AppKit
import Foundation

// 应用入口. 使用 AppKit 管理生命周期, 便于控制激活策略与窗口显隐.
@main
struct VDDXMain {
    @MainActor
    static func main() {
        AppPaths.prepareDirectories()

        let environmentLevel = LogLevel(name: ProcessInfo.processInfo.environment["VDDX_LOG_LEVEL"] ?? "") ?? .info
        let mirrorToStderr = ProcessInfo.processInfo.environment["VDDX_LOG_STDERR"] != "0"
        Log.shared.configure(level: environmentLevel, fileURL: AppPaths.logFileURL, mirrorToStderr: mirrorToStderr)

        let app = NSApplication.shared
        // 首次创建普通主窗口前先声明为普通应用, 避免以辅助应用身份创建窗口.
        app.setActivationPolicy(.regular)

        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
