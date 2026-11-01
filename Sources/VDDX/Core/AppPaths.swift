import Foundation

/// 应用在磁盘上的位置约定. 所有路径都跟随 `$HOME` 的平台 API 解析, 不手写家目录.
enum AppPaths {
    /// 用于组织目录的标识, 与 Info.plist 中的 CFBundleIdentifier 保持一致.
    static let identifier = Bundle.main.bundleIdentifier ?? "com.azazo1.vddx"

    /// fake 构建通过 Info.plist 的 VDDXChannel 标记, 数据目录独立.
    static var channelSuffix: String {
        (Bundle.main.object(forInfoDictionaryKey: "VDDXChannel") as? String) == "fake" ? "-fake" : ""
    }

    static var dataDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["VDDX_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(identifier + channelSuffix, isDirectory: true)
    }

    static var logDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["VDDX_LOG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return base.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(identifier + channelSuffix, isDirectory: true)
    }

    static var logFileURL: URL {
        if let override = ProcessInfo.processInfo.environment["VDDX_LOG_FILE"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: false)
        }
        return logDirectory.appendingPathComponent("vddx.log", isDirectory: false)
    }

    static func prepareDirectories() {
        for directory in [dataDirectory, logDirectory, logFileURL.deletingLastPathComponent()] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
