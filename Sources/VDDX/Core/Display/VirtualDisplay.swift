import CoreGraphics
import Foundation

/// 一块已经上线的虚拟屏.
///
/// 实际持有它的是 `DisplayHost` 子进程: 进程活着屏就在, 子进程退出屏就消失.
@MainActor
final class VirtualDisplay: Identifiable {
    nonisolated let id: UUID
    let displayID: CGDirectDisplayID
    private(set) var profile: DisplayProfile
    private let host: DisplayHost
    private var destroyed = false

    var isAlive: Bool {
        host.isRunning && CGDisplayIsActive(displayID) != 0
    }

    init(profile: DisplayProfile, host: DisplayHost) {
        self.id = profile.id
        self.profile = profile
        self.host = host
        self.displayID = host.displayID
    }

    func updateProfile(_ profile: DisplayProfile) {
        self.profile = profile
    }

    /// 结束 host 进程, 系统随之移除虚拟屏.
    func destroy() {
        guard !destroyed else { return }
        destroyed = true
        host.terminate()
        Log.shared.info("虚拟屏已销毁: \(profile.name) displayID=\(displayID)")
    }

    deinit {
        host.terminate()
    }
}
