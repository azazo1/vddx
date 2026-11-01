import AppKit
import SwiftUI

@MainActor
final class UpdateWindowController: NSWindowController {
    private let model: AppModel
    private let onDownload: (UpdateRelease) -> Void
    private let onInstall: (UpdateRelease, URL) -> Void
    private let onSkip: (UpdateRelease) -> Void
    private let onOpenReleasePage: () -> Void

    init(
        model: AppModel,
        onDownload: @escaping (UpdateRelease) -> Void,
        onInstall: @escaping (UpdateRelease, URL) -> Void,
        onSkip: @escaping (UpdateRelease) -> Void,
        onOpenReleasePage: @escaping () -> Void
    ) {
        self.model = model
        self.onDownload = onDownload
        self.onInstall = onInstall
        self.onSkip = onSkip
        self.onOpenReleasePage = onOpenReleasePage

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "软件更新"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: EmptyView())
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(with release: UpdateRelease) {
        guard let window else { return }
        let view = UpdateView(
            model: model,
            release: release,
            onDownload: onDownload,
            onInstall: onInstall,
            onSkip: onSkip,
            onOpenReleasePage: onOpenReleasePage
        )
        window.contentViewController = NSHostingController(rootView: view)
        window.title = "软件更新 - \(release.tagName)"
    }
}
