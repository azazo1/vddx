import AppKit
import CoreGraphics
import CVirtualDisplayBridge
import Foundation

enum VirtualDisplayError: LocalizedError {
    case bridgeUnavailable
    case invalidProfile(String)
    case creationFailed(String)
    case invalidDisplayID

    var errorDescription: String? {
        switch self {
        case .bridgeUnavailable:
            return "当前系统不提供创建虚拟屏所需的接口"
        case .invalidProfile(let reason):
            return "虚拟屏配置无效: \(reason)"
        case .creationFailed(let message):
            return "虚拟屏创建失败: \(message)"
        case .invalidDisplayID:
            return "虚拟屏创建后未获得有效的显示器 ID"
        }
    }
}

/// 虚拟屏的创建, 销毁与状态维护.
@MainActor
final class VirtualDisplayManager: ObservableObject {
    @Published private(set) var displays: [VirtualDisplay] = []
    /// 系统显示器配置变化时递增, 供界面刷新存活状态.
    @Published private(set) var screenChangeTick = 0
    @Published private(set) var lastError: String?

    private let store: DisplayProfileStore
    private static let vendorID: UInt32 = 0x1234
    private static let productID: UInt32 = 0x5678

    init(store: DisplayProfileStore? = nil) {
        self.store = store ?? DisplayProfileStore()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleScreenParametersChanged() {
        screenChangeTick += 1
        let dead = displays.filter { !$0.isAlive }.map(\.profile.name)
        if !dead.isEmpty {
            Log.shared.warn("以下虚拟屏在显示器配置变化后不再存活: \(dead.joined(separator: ", "))")
        }
    }

    /// 应用启动时重建此前标记为自动恢复的虚拟屏.
    func restoreSavedDisplays() {
        let profiles = store.profiles
        guard !profiles.isEmpty else {
            Log.shared.info("没有需要自动恢复的虚拟屏")
            return
        }
        Log.shared.info("开始恢复 \(profiles.count) 块虚拟屏")
        for profile in profiles {
            do {
                try create(profile, persist: false)
            } catch {
                Log.shared.error("恢复虚拟屏 \(profile.name) 失败: \(error.localizedDescription)")
                lastError = error.localizedDescription
            }
        }
    }

    @discardableResult
    func create(_ profile: DisplayProfile, persist: Bool = true) throws -> VirtualDisplay {
        guard VDXBridgeIsAvailable() else {
            throw VirtualDisplayError.bridgeUnavailable
        }
        guard profile.isValid else {
            throw VirtualDisplayError.invalidProfile("分辨率或刷新率超出支持范围")
        }

        let started = DispatchTime.now().uptimeNanoseconds
        let host: DisplayHost
        do {
            host = try DisplayHost.launch(profile: profile)
        } catch {
            Log.shared.error("创建虚拟屏 \(profile.name) 失败: \(error.localizedDescription)")
            throw error
        }
        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        let displayID = host.displayID

        host.observeTermination { [weak self] in
            guard let self else { return }
            self.screenChangeTick += 1
            Log.shared.warn("虚拟屏进程已退出: \(profile.name)")
        }
        let display = VirtualDisplay(profile: profile, host: host)
        displays.append(display)
        if persist {
            syncStore(with: profile)
        }
        Log.shared.info(
            "已创建虚拟屏 \(profile.name) displayID=\(displayID) "
                + "\(profile.logicalWidth)x\(profile.logicalHeight)@\(profile.refreshRateLabel) "
                + "hiDPI=\(profile.hiDPI) 耗时 \(String(format: "%.1f", elapsedMS)) ms"
        )

        if CGDisplayIsActive(displayID) == 0 {
            Log.shared.warn("虚拟屏 \(displayID) 创建后尚未被系统标记为活动, 可能仍在初始化")
        }
        return display
    }

    /// 销毁一块虚拟屏, 但保留它的自动恢复配置.
    func destroy(_ display: VirtualDisplay) {
        display.destroy()
        displays.removeAll { $0.id == display.id }
    }

    /// 销毁并从自动恢复配置中移除.
    func forget(_ display: VirtualDisplay) {
        destroy(display)
        store.remove(id: display.id)
        Log.shared.info("已移除虚拟屏配置: \(display.profile.name)")
    }

    func update(_ display: VirtualDisplay, with profile: DisplayProfile) {
        display.updateProfile(profile)
        syncStore(with: profile)
    }

    /// 按新配置重建一块虚拟屏. 分辨率与刷新率的修改通过重建生效.
    @discardableResult
    func rebuild(_ display: VirtualDisplay, with profile: DisplayProfile) throws -> VirtualDisplay {
        let replacedID = display.id
        destroy(display)
        var newProfile = profile
        newProfile.id = replacedID
        let newDisplay = try create(newProfile, persist: true)
        Log.shared.info("已按新配置重建虚拟屏: \(newProfile.name)")
        return newDisplay
    }

    func destroyAll() {
        for display in displays {
            display.destroy()
        }
        displays.removeAll()
    }

    var savedProfiles: [DisplayProfile] { store.profiles }

    private func syncStore(with profile: DisplayProfile) {
        if profile.autoRestore {
            store.set(profile)
        } else {
            store.remove(id: profile.id)
        }
    }

}
