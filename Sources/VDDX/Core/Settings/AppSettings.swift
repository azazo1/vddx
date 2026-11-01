import Foundation

/// 通用设置.
struct GeneralSettings: Codable, Equatable {
    /// 启动时不自动显示主窗口, 仅常驻菜单栏.
    var hideMainWindowOnLaunch: Bool = false
    /// 主窗口隐藏时同时隐藏 Dock 图标.
    var hideDockWhenWindowHidden: Bool = true
    /// 日志级别, 取值为 trace/debug/info/warn/error.
    var logLevel: String = "info"

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hideMainWindowOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .hideMainWindowOnLaunch) ?? false
        hideDockWhenWindowHidden = try container.decodeIfPresent(Bool.self, forKey: .hideDockWhenWindowHidden) ?? true
        logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel) ?? "info"
    }
}

/// 更新检查设置.
struct UpdateSettings: Codable, Equatable {
    var automaticallyChecks: Bool = true
    var lastCheckAt: Date?
    /// 用户选择跳过的版本号, 例如 `v0.2.0`.
    var skippedVersion: String?

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        automaticallyChecks = try container.decodeIfPresent(Bool.self, forKey: .automaticallyChecks) ?? true
        lastCheckAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckAt)
        skippedVersion = try container.decodeIfPresent(String.self, forKey: .skippedVersion)
    }
}

/// 应用设置文件.
///
/// `version` 用于在不兼容时执行迁移, 见 `SettingsMigrator`.
struct AppSettings: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = AppSettings.currentVersion
    var general: GeneralSettings = GeneralSettings()
    var updates: UpdateSettings = UpdateSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        general = try container.decodeIfPresent(GeneralSettings.self, forKey: .general) ?? GeneralSettings()
        updates = try container.decodeIfPresent(UpdateSettings.self, forKey: .updates) ?? UpdateSettings()
    }
}

/// 设置文件迁移.
///
/// 读取原始 JSON 后先升级 `version`, 再交给 `JSONDecoder` 解析,
/// 这样旧版本缺少的字段会使用默认值.
enum SettingsMigrator {
    enum MigrationError: LocalizedError {
        case unreadable
        case tooNew(Int)
        case invalidStructure

        var errorDescription: String? {
            switch self {
            case .unreadable: return "设置文件不是有效的 JSON 对象"
            case .tooNew(let version): return "设置文件版本 \(version) 高于当前支持的 \(AppSettings.currentVersion)"
            case .invalidStructure: return "设置文件结构无效"
            }
        }
    }

    static func migrate(data: Data) throws -> AppSettings {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MigrationError.unreadable
        }
        let version = object["version"] as? Int ?? 0
        guard version <= AppSettings.currentVersion else {
            throw MigrationError.tooNew(version)
        }

        // 逐版本迁移. 当前只有 v1, 缺少 version 字段的旧文件按 v0 处理.
        var current = version
        if current < 1 {
            object["version"] = 1
            current = 1
        }

        let migrated = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(AppSettings.self, from: migrated)
        } catch {
            throw MigrationError.invalidStructure
        }
    }
}
