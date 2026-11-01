import AppKit
import Foundation
import ScreenCaptureKit

/// 把一块虚拟屏的画面显示在一个普通窗口里.
@MainActor
final class MirrorWindowController: NSWindowController, NSWindowDelegate {
    private let display: VirtualDisplay
    private let model: AppModel
    private let previewView = SampleBufferDisplayView()
    private let session = MirrorCaptureSession()
    private let statusLabel = NSTextField(labelWithString: "正在准备...")
    private let grantButton = NSButton(title: "打开屏幕录制设置", target: nil, action: nil)

    var onClose: (() -> Void)?

    init(display: VirtualDisplay, model: AppModel) {
        self.display = display
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(display.profile.name) - 镜像"
        window.minSize = NSSize(width: 480, height: 270)
        window.center()

        super.init(window: window)
        window.delegate = self

        let aspect = CGFloat(display.profile.logicalWidth) / CGFloat(max(display.profile.logicalHeight, 1))
        var width: CGFloat = 960
        var height: CGFloat = width / aspect
        if let visible = NSScreen.main?.visibleFrame.size {
            let maxWidth = visible.width * 0.8
            let maxHeight = visible.height * 0.8
            if width > maxWidth { width = maxWidth; height = width / aspect }
            if height > maxHeight { height = maxHeight; width = height * aspect }
        }
        window.setContentSize(NSSize(width: width, height: height))
        window.center()

        configureContent()
        session.onSampleBuffer = { [weak self] buffer in
            self?.previewView.enqueue(buffer)
        }
        session.onStatusChange = { [weak self] status in
            self?.apply(status)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func configureContent() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        window?.contentView = container

        previewView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(previewView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.font = .systemFont(ofSize: 12)
        container.addSubview(statusLabel)

        grantButton.translatesAutoresizingMaskIntoConstraints = false
        grantButton.bezelStyle = .rounded
        grantButton.target = self
        grantButton.action = #selector(openPermissionSettings)
        grantButton.isHidden = true
        container.addSubview(grantButton)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: container.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -14),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            grantButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            grantButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 14)
        ])
    }

    func startCapture() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.start(
                    displayID: self.display.displayID,
                    refreshRate: self.display.profile.refreshRate
                )
            } catch {
                Log.shared.error("镜像启动失败: \(error.localizedDescription)")
            }
        }
    }

    func stopCapture() {
        session.stop()
        previewView.clear()
    }

    private func apply(_ status: MirrorCaptureSession.Status) {
        switch status {
        case .idle:
            statusLabel.stringValue = "已停止"
            statusLabel.isHidden = false
        case .starting:
            statusLabel.stringValue = "正在连接虚拟屏..."
            statusLabel.isHidden = false
            grantButton.isHidden = true
        case .running:
            statusLabel.stringValue = ""
            statusLabel.isHidden = true
            grantButton.isHidden = true
        case .failed(let message):
            statusLabel.stringValue = message
            statusLabel.isHidden = false
            grantButton.isHidden = ScreenCapturePermission.isGranted
        }
    }

    @objc private func openPermissionSettings() {
        ScreenCapturePermission.openSystemSettings()
    }

    func windowWillClose(_ notification: Notification) {
        stopCapture()
        onClose?()
    }

    deinit {
        session.stop()
    }
}
