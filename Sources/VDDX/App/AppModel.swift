import AppKit
import Foundation

/// 应用级状态聚合.
@MainActor
final class AppModel: ObservableObject {
    let settingsStore: SettingsStore
    let displayManager: VirtualDisplayManager
    let updates: UpdateController

    @Published var settings: AppSettings
    @Published var settingsWarning: String?
    /// 从托盘触发的"新建虚拟屏"请求, 主窗口消费后复位.
    @Published var createDisplayRequest = false

    init() {
        let store = SettingsStore()
        self.settingsStore = store
        self.settings = store.settings
        self.settingsWarning = store.loadWarning
        self.displayManager = VirtualDisplayManager()
        self.updates = UpdateController()
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
        settingsStore.apply(copy)
        applyLogLevel()
    }

    func applyLogLevel() {
        guard let level = LogLevel(name: settings.general.logLevel) else {
            Log.shared.warn("未知日志级别: \(settings.general.logLevel), 保持当前级别")
            return
        }
        Log.shared.setLevel(level)
    }

    /// 检查更新, 并处理用户"跳过此版本"的选择.
    func checkForUpdates(silent: Bool) async {
        await updates.check(silent: silent)
        if case .available(let release) = updates.state,
           settings.updates.skippedVersion == release.tagName {
            updates.dismissAvailable()
            Log.shared.info("版本 \(release.tagName) 已被用户跳过")
        }
    }

    /// 新虚拟屏的默认名称, 避免与现有名称重复.
    var suggestedDisplayName: String {
        let existing = Set(displayManager.displays.map(\.profile.name))
        var index = 1
        while existing.contains(String(format: "VDDX %02d", index)) {
            index += 1
        }
        return String(format: "VDDX %02d", index)
    }
}
