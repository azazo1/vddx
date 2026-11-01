import Foundation

/// 设置文件的加载与保存.
@MainActor
final class SettingsStore {
    private let url: URL
    private(set) var settings = AppSettings()
    /// 加载失败时保留的警告信息, 供界面提示.
    private(set) var loadWarning: String?

    init(url: URL = AppPaths.dataDirectory.appendingPathComponent("settings.json")) {
        self.url = url
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.shared.info("未找到设置文件, 使用默认设置: \(url.path)")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            settings = try SettingsMigrator.migrate(data: data)
            Log.shared.info("已加载设置: version=\(settings.version)")
        } catch {
            let backup = url.appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: backup)
            loadWarning = "设置文件无法读取, 已备份到 \(backup.lastPathComponent) 并恢复默认设置"
            Log.shared.error("设置文件加载失败: \(error.localizedDescription), 已备份到 \(backup.path)")
            settings = AppSettings()
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(settings)
            try data.write(to: url, options: .atomic)
            Log.shared.debug("设置已保存")
        } catch {
            Log.shared.error("设置保存失败: \(error.localizedDescription)")
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        save()
    }

    func apply(_ newSettings: AppSettings) {
        settings = newSettings
        save()
    }
}
