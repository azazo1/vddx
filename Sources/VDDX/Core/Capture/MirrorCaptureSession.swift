import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permissionDenied
    case displayNotFound(CGDirectDisplayID)
    case streamFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "需要屏幕录制权限才能显示虚拟屏画面"
        case .displayNotFound(let id):
            return "系统未找到显示器 \(id), 该虚拟屏可能已失效"
        case .streamFailed(let message):
            return "画面捕获失败: \(message)"
        }
    }
}

/// 屏幕录制权限查询与引导.
enum ScreenCapturePermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// 请求权限. macOS 15 起系统不再对该权限自动弹窗, 需要引导用户去系统设置手动添加.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}

/// 捕获一块显示器的画面, 把完整帧交给上层渲染.
///
/// 帧回调发生在内部串行队列, 不代表主线程.
final class MirrorCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    enum Status: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    /// 在内部串行队列上回调.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?
    /// 在主线程上回调.
    var onStatusChange: ((Status) -> Void)?

    private let sampleQueue = DispatchQueue(label: "dev.vddx.mirror-capture", qos: .userInitiated)
    private var stream: SCStream?

    private(set) var status: Status = .idle {
        didSet {
            guard status != oldValue else { return }
            let status = status
            DispatchQueue.main.async { [weak self] in
                self?.onStatusChange?(status)
            }
        }
    }

    func start(displayID: CGDirectDisplayID, refreshRate: Double) async throws {
        stop()

        guard ScreenCapturePermission.isGranted else {
            status = .failed(CaptureError.permissionDenied.localizedDescription)
            throw CaptureError.permissionDenied
        }

        status = .starting
        Log.shared.info("开始捕获显示器 \(displayID), 刷新率 \(refreshRate)")

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            status = .failed(error.localizedDescription)
            throw CaptureError.streamFailed(error.localizedDescription)
        }

        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            status = .failed(CaptureError.displayNotFound(displayID).localizedDescription)
            throw CaptureError.displayNotFound(displayID)
        }

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = scDisplay.width
        configuration.height = scDisplay.height
        let rate = max(Int(refreshRate.rounded()), 24)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(rate))
        configuration.queueDepth = 3
        configuration.showsCursor = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = false
        configuration.preservesAspectRatio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
        } catch {
            status = .failed(error.localizedDescription)
            throw CaptureError.streamFailed(error.localizedDescription)
        }
        self.stream = stream
        status = .running
        Log.shared.info("捕获已启动: \(scDisplay.width)x\(scDisplay.height)@\(rate)Hz")
    }

    func stop() {
        guard let stream else { return }
        stream.stopCapture { error in
            if let error {
                Log.shared.warn("停止捕获时出错: \(error.localizedDescription)")
            }
        }
        self.stream = nil
        status = .idle
        Log.shared.info("捕获已停止")
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        guard isCompleteFrame(sampleBuffer) else { return }
        onSampleBuffer?(sampleBuffer)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.shared.error("捕获意外停止: \(error.localizedDescription)")
        status = .failed(error.localizedDescription)
        self.stream = nil
    }

    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            let frameStatus = SCFrameStatus(rawValue: rawStatus) else {
            // 没有附带状态信息时按完整帧处理.
            return true
        }
        return frameStatus == .complete
    }
}
