import AppKit
import CryptoKit
import Foundation

/// 一个可用的新版本.
struct UpdateRelease: Equatable, Identifiable {
    let tagName: String
    let version: String
    let title: String
    let notes: String
    let dmgURL: URL
    let dmgName: String
    let checksumsURL: URL?

    var id: String { tagName }
}

/// 版本检查与安装.
///
/// 安装流程: 下载 dmg -> 校验 SHA256 -> 生成脱离进程的替换脚本 -> 用户确认后交接.
@MainActor
final class UpdateController: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case downloading(UpdateRelease)
        case ready(UpdateRelease, URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// 静默检查发现的新版本号, 供状态栏展示.
    @Published private(set) var availableVersion: String?

    private let session: URLSession
    private var lastSilentCheck: Date?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = ["User-Agent": "VDDX/\(AppInfo.numericVersion)"]
        session = URLSession(configuration: configuration)
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading: return true
        default: return false
        }
    }

    /// 忽略当前可用的新版本 (用户选择跳过).
    func dismissAvailable() {
        availableVersion = nil
        state = .idle
    }

    func check(silent: Bool) async {
        guard !AppInfo.isDevBuild else {
            Log.shared.info("开发构建跳过更新检查")
            return
        }
        guard !isBusy else { return }
        if silent {
            if let lastSilentCheck, Date().timeIntervalSince(lastSilentCheck) < 3600 * 6 {
                return
            }
            lastSilentCheck = Date()
        } else {
            state = .checking
        }

        do {
            let release = try await fetchLatestRelease()
            state = .idle
            if VersionComparison.isNewer(release.version, than: AppInfo.numericVersion) {
                availableVersion = release.tagName
                if silent {
                    state = .available(release)
                } else {
                    state = .available(release)
                }
                Log.shared.info("发现新版本: \(release.tagName), 当前 \(AppInfo.displayVersion)")
            } else {
                availableVersion = nil
                state = .upToDate
                Log.shared.info("已是最新版本: \(AppInfo.displayVersion)")
            }
        } catch {
            Log.shared.warn("检查更新失败: \(error.localizedDescription)")
            if !silent {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func download(_ release: UpdateRelease) async {
        state = .downloading(release)
        do {
            let url = try await downloadPackage(for: release)
            state = .ready(release, url)
            Log.shared.info("更新包已下载并校验: \(url.path)")
        } catch {
            Log.shared.error("更新包下载失败: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    /// 交接给替换脚本并退出应用. 调用前应确保用户已经确认.
    func installAndRelaunch(_ release: UpdateRelease, packageURL: URL) throws {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            throw UpdateError.notApplicationBundle
        }
        let scriptURL = try Self.writeInstallScript(
            appPath: appURL.path,
            dmgPath: packageURL.path,
            appPID: ProcessInfo.processInfo.processIdentifier
        )
        Log.shared.info("启动替换脚本: \(scriptURL.path)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        try process.run()
        NSApp.terminate(nil)
    }

    // MARK: - 网络

    private func fetchLatestRelease() async throws -> UpdateRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(AppInfo.repositorySlug)/releases/latest") else {
            throw UpdateError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdateError.invalidResponse
        }
        let tagName = object["tag_name"] as? String ?? ""
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        guard !version.isEmpty else { throw UpdateError.invalidResponse }

        let assets = (object["assets"] as? [[String: Any]]) ?? []
        let architecture = Self.currentArchitecture()
        let dmg = assets.first { asset in
            let name = asset["name"] as? String ?? ""
            return name.hasSuffix("-macos-\(architecture).dmg")
        }
        guard let dmg,
              let name = dmg["name"] as? String,
              let downloadURLString = dmg["browser_download_url"] as? String,
              let downloadURL = URL(string: downloadURLString) else {
            throw UpdateError.noMatchingAsset(architecture)
        }
        let checksums = assets.first { ($0["name"] as? String) == "SHA256SUMS" }
        let checksumsURL = (checksums?["browser_download_url"] as? String).flatMap(URL.init(string:))

        return UpdateRelease(
            tagName: tagName,
            version: version,
            title: object["name"] as? String ?? tagName,
            notes: object["body"] as? String ?? "",
            dmgURL: downloadURL,
            dmgName: name,
            checksumsURL: checksumsURL
        )
    }

    private func downloadPackage(for release: UpdateRelease) async throws -> URL {
        let directory = AppPaths.dataDirectory.appendingPathComponent("updates", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(release.dmgName)

        let (temporary, response) = try await session.download(from: release.dmgURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)

        if let checksumsURL = release.checksumsURL {
            let expected = try await fetchChecksum(for: release.dmgName, from: checksumsURL)
            let actual = try Self.sha256(of: destination)
            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                try? FileManager.default.removeItem(at: destination)
                throw UpdateError.checksumMismatch(expected: expected, actual: actual)
            }
            Log.shared.info("SHA256 校验通过: \(actual)")
        } else {
            Log.shared.warn("发布未提供 SHA256SUMS, 跳过校验")
        }
        return destination
    }

    private func fetchChecksum(for fileName: String, from url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw UpdateError.invalidResponse
        }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let name = parts.last.map(String.init) ?? ""
            if name == fileName || name == "./\(fileName)" {
                return String(parts[0])
            }
        }
        throw UpdateError.checksumMissing(fileName)
    }

    // MARK: - 工具

    private static func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    private static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func writeInstallScript(appPath: String, dmgPath: String, appPID: Int32) throws -> URL {
        let directory = AppPaths.dataDirectory.appendingPathComponent("updates", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("install.sh")
        let logURL = directory.appendingPathComponent("install.log")
        let script = """
        #!/bin/bash
        set -uo pipefail
        APP_PID=\(appPID)
        APP_PATH="\(appPath)"
        DMG_PATH="\(dmgPath)"
        LOG="\(logURL.path)"

        echo "[update] $(date '+%F %T') 等待进程 $APP_PID 退出" >> "$LOG"
        while kill -0 "$APP_PID" 2>/dev/null; do sleep 0.2; done

        MOUNT=$(mktemp -d "${TMPDIR:-/tmp}/vddx-update.XXXXXX")
        if ! hdiutil attach "$DMG_PATH" -nobrowse -quiet -mountpoint "$MOUNT" >> "$LOG" 2>&1; then
            echo "[update] 挂载失败" >> "$LOG"
            open "$APP_PATH"
            exit 1
        fi

        STAGING="$MOUNT/VDDX.app"
        if [ ! -d "$STAGING" ]; then
            echo "[update] 更新包内未找到 VDDX.app" >> "$LOG"
            hdiutil detach "$MOUNT" -quiet >> "$LOG" 2>&1
            open "$APP_PATH"
            exit 1
        fi

        BACKUP="${APP_PATH}.old"
        rm -rf "$BACKUP"
        if [ -d "$APP_PATH" ]; then
            mv "$APP_PATH" "$BACKUP" >> "$LOG" 2>&1
        fi
        if ditto "$STAGING" "$APP_PATH" >> "$LOG" 2>&1; then
            xattr -dr com.apple.quarantine "$APP_PATH" >> "$LOG" 2>&1 || true
            rm -rf "$BACKUP"
            echo "[update] 替换完成" >> "$LOG"
        else
            echo "[update] 替换失败, 回滚" >> "$LOG"
            rm -rf "$APP_PATH"
            if [ -d "$BACKUP" ]; then mv "$BACKUP" "$APP_PATH"; fi
        fi

        hdiutil detach "$MOUNT" -quiet >> "$LOG" 2>&1 || true
        open "$APP_PATH"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }
}

enum UpdateError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case noMatchingAsset(String)
    case checksumMissing(String)
    case checksumMismatch(expected: String, actual: String)
    case notApplicationBundle

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "无法解析更新信息"
        case .httpStatus(let code):
            return "请求失败, HTTP 状态码 \(code)"
        case .noMatchingAsset(let arch):
            return "发布中没有适用于 \(arch) 的安装包"
        case .checksumMissing(let name):
            return "SHA256SUMS 中缺少 \(name) 的校验值"
        case .checksumMismatch(let expected, let actual):
            return "校验值不匹配, 期望 \(expected), 实际 \(actual)"
        case .notApplicationBundle:
            return "当前不在应用包内运行, 无法自动更新"
        }
    }
}

enum VersionComparison {
    /// 比较两个版本号, 忽略 `v` 前缀与预发布后缀.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = numericParts(lhs)
        let rhsParts = numericParts(rhs)
        for index in 0..<max(lhsParts.count, rhsParts.count) {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left != right {
                return left > right ? .orderedDescending : .orderedAscending
            }
        }
        return .orderedSame
    }

    private static func numericParts(_ version: String) -> [Int] {
        var text = version.hasPrefix("v") ? String(version.dropFirst()) : version
        if let dash = text.firstIndex(of: "-") {
            text = String(text[..<dash])
        }
        if let plus = text.firstIndex(of: "+") {
            text = String(text[..<plus])
        }
        return text.split(separator: ".").map { Int($0) ?? 0 }
    }
}
