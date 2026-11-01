import AppKit
import SwiftUI

/// 主窗口. 使用 AppKit 窗口加 SwiftUI 内容, 便于精确控制显示/隐藏与尺寸记忆.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var isInFullScreenTransition = false

    var onCloseRequest: (() -> Void)?
    var onOpenMirror: ((VirtualDisplay) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCheckUpdates: (() -> Void)?
    var onOpenUpdateWindow: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        let restored = WindowStateStore.loadSize().map(WindowStateStore.clamp)
            ?? NSSize(width: 960, height: 640)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: restored),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "VDDX"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let root = MainWindowView(
            model: model,
            onMirror: { [weak self] display in self?.onOpenMirror?(display) },
            onOpenSettings: { [weak self] in self?.onOpenSettings?() },
            onCheckUpdates: { [weak self] in self?.onCheckUpdates?() },
            onOpenUpdateWindow: { [weak self] in self?.onOpenUpdateWindow?() }
        )
        window.contentViewController = NSHostingController(rootView: root)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    func prepareForTermination() {
        saveSizeIfNeeded()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCloseRequest?()
        return false
    }

    func windowDidResize(_ notification: Notification) {
        guard !isInFullScreenTransition,
              let window,
              !window.styleMask.contains(.fullScreen) else {
            return
        }
        saveSizeIfNeeded()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        isInFullScreenTransition = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        isInFullScreenTransition = false
        saveSizeIfNeeded()
    }

    private func saveSizeIfNeeded() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let size = window.contentView?.frame.size ?? window.frame.size
        WindowStateStore.saveSize(size)
    }
}
