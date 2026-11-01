import Foundation

/// 应用身份与版本信息.
///
/// 版本号由打包脚本注入 Info.plist:
/// - `CFBundleShortVersionString` 为不带前缀的版本号, 例如 `0.1.0`
/// - `VDDXVersionDisplay` 为界面展示的版本号, 例如 `v0.1.0` 或 `v0.1.0-a1b2c3d`
///
/// 日常开发构建不注入版本信息, 展示为 `dev-build`.
enum AppInfo {
    static let appName = "VDDX"

    static let repositoryOwner = "azazo1"
    static let repositoryName = "vddx"
    static var repositorySlug: String { "\(repositoryOwner)/\(repositoryName)" }
    static var repositoryURL: URL { URL(string: "https://github.com/\(repositorySlug)")! }
    static var releasesURL: URL { repositoryURL.appendingPathComponent("releases") }

    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? AppPaths.identifier }

    /// 无 bundle (例如 `swift run`) 时返回 nil.
    static var bundle: Bundle? {
        Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : nil
    }

    static var displayVersion: String {
        if let injected = Bundle.main.object(forInfoDictionaryKey: "VDDXVersionDisplay") as? String,
           !injected.trimmingCharacters(in: .whitespaces).isEmpty {
            return injected
        }
        if let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           short != "0.0.0" {
            return "v\(short)"
        }
        return "dev-build"
    }

    /// 不带 `v` 前缀的版本号, 用于比较.
    static var numericVersion: String {
        let trimmed = displayVersion.hasPrefix("v") ? String(displayVersion.dropFirst()) : displayVersion
        return trimmed
    }

    static var isDevBuild: Bool { displayVersion == "dev-build" }

    static var channel: String {
        (Bundle.main.object(forInfoDictionaryKey: "VDDXChannel") as? String) ?? "release"
    }

    static var distributionForm: String {
        (Bundle.main.object(forInfoDictionaryKey: "VDDXDistributionForm") as? String) ?? "dev"
    }
}
