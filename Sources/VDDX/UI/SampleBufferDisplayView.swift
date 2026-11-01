import AVFoundation
import AppKit
import CoreMedia

/// 直接承载 `AVSampleBufferDisplayLayer` 的视图, 避免每帧转成图片.
final class SampleBufferDisplayView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let host = CALayer()
        host.backgroundColor = NSColor.black.cgColor
        layer = host
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        host.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    /// 可以在捕获队列上调用.
    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    func clear() {
        displayLayer.flushAndRemoveImage()
    }
}
