import CoreGraphics
import CVirtualDisplayBridge
import Foundation

/// 一块已经上线的虚拟屏.
///
/// 进程存活期间该屏存在; 调用 `destroy()` 或进程退出后系统会回收它.
@MainActor
final class VirtualDisplay: Identifiable {
    nonisolated let id: UUID
    let displayID: CGDirectDisplayID
    let createdAt = Date()
    private(set) var profile: DisplayProfile
    private var handle: VDXDisplayHandle?

    var isAlive: Bool {
        handle != nil && CGDisplayIsActive(displayID) != 0
    }

    init(profile: DisplayProfile, handle: VDXDisplayHandle, displayID: CGDirectDisplayID) {
        self.id = profile.id
        self.profile = profile
        self.handle = handle
        self.displayID = displayID
    }

    func updateProfile(_ profile: DisplayProfile) {
        self.profile = profile
    }

    /// 释放底层虚拟屏, 之后 `isAlive` 为 false.
    func destroy() {
        guard let handle else { return }
        VDXDisplayDestroy(handle)
        self.handle = nil
        Log.shared.info("虚拟屏已销毁: \(profile.name) displayID=\(displayID)")
    }

    deinit {
        if let handle {
            VDXDisplayDestroy(handle)
        }
    }
}
