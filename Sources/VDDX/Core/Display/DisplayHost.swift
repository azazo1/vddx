import CoreGraphics
import Foundation

enum DisplayHostError: LocalizedError {
    case executableNotFound
    case launchFailed(String)
    case handshakeFailed(String)
    case creationFailed(String)
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .executableNotFound: return "找不到应用可执行文件, 无法启动虚拟屏进程"
        case .launchFailed(let message): return "虚拟屏进程启动失败: \(message)"
        case .handshakeFailed(let message): return "虚拟屏进程握手失败: \(message)"
        case .creationFailed(let message): return "虚拟屏创建失败: \(message)"
        case .invalidRequest: return "虚拟屏配置无法编码"
        }
    }
}

/// 一块虚拟屏对应的 host 子进程.
///
/// `CGVirtualDisplay` 在进程内释放后不会从系统移除, 只有进程退出时系统才会回收.
/// 因此每块虚拟屏由一个独立子进程持有:
/// - 删除虚拟屏 = 结束子进程
/// - 主进程崩溃 = 子进程的 stdin 收到 EOF, 自行退出
final class DisplayHost {
    struct Request: Codable {
        var name: String
        var logicalWidth: Int
        var logicalHeight: Int
        var refreshRate: Double
        var hiDPI: Bool
        var maxPixelsWide: Int
        var maxPixelsHigh: Int
        var sizeMillimetersWide: Double
        var sizeMillimetersHigh: Double
        var serial: UInt32
        var product: UInt32
        var vendor: UInt32
    }

    struct Response: Codable {
        var displayID: UInt32?
        var error: String?
    }

    let displayID: CGDirectDisplayID

    private let process: Process
    private let inputPipe: Pipe
    private let outputPipe: Pipe
    private let lock = NSLock()

    private init(process: Process, inputPipe: Pipe, outputPipe: Pipe, displayID: CGDirectDisplayID) {
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.displayID = displayID
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process.isRunning
    }

    /// 子进程意外退出时在主线程回调.
    func observeTermination(_ handler: @escaping () -> Void) {
        process.terminationHandler = { _ in
            DispatchQueue.main.async { handler() }
        }
    }

    static func launch(profile: DisplayProfile) throws -> DisplayHost {
        let size = DisplayModeCatalog.millimeters(
            forLogicalWidth: profile.logicalWidth,
            height: profile.logicalHeight
        )
        let request = Request(
            name: profile.name,
            logicalWidth: profile.logicalWidth,
            logicalHeight: profile.logicalHeight,
            refreshRate: profile.refreshRate,
            hiDPI: profile.hiDPI,
            maxPixelsWide: profile.pixelWidth,
            maxPixelsHigh: profile.pixelHeight,
            sizeMillimetersWide: size.width,
            sizeMillimetersHigh: size.height,
            serial: serialNumber(for: profile.id),
            product: 0x5678,
            vendor: 0x1234
        )
        let encoded = try JSONEncoder().encode(request)
        guard let json = String(data: encoded, encoding: .utf8) else {
            throw DisplayHostError.invalidRequest
        }
        guard let executable = Bundle.main.executableURL else {
            throw DisplayHostError.executableNotFound
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--display-host", json]
        process.standardError = FileHandle.standardError

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe

        do {
            try process.run()
        } catch {
            throw DisplayHostError.launchFailed(error.localizedDescription)
        }

        // 握手: 子进程创建成功后向 stdout 输出一行 JSON.
        var buffer = Data()
        let reader = outputPipe.fileHandleForReading
        while !buffer.contains(0x0A) {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
        }
        guard let newline = buffer.firstIndex(of: 0x0A) else {
            process.terminate()
            throw DisplayHostError.handshakeFailed("子进程没有返回显示器 ID")
        }
        let line = Data(buffer[buffer.startIndex..<newline])
        guard let response = try? JSONDecoder().decode(Response.self, from: line) else {
            process.terminate()
            throw DisplayHostError.handshakeFailed("握手数据无法解析")
        }
        guard let displayID = response.displayID, displayID != 0 else {
            process.terminate()
            throw DisplayHostError.creationFailed(response.error ?? "未知原因")
        }

        Log.shared.info("虚拟屏进程已启动: \(profile.name) displayID=\(displayID) pid=\(process.processIdentifier)")
        return DisplayHost(process: process, inputPipe: inputPipe, outputPipe: outputPipe, displayID: displayID)
    }

    /// 结束子进程并关闭管道. 重复调用安全.
    func terminate() {
        lock.lock()
        let running = process.isRunning
        let process = self.process
        let input = inputPipe
        let output = outputPipe
        lock.unlock()

        // 先关闭 stdin, 让子进程的阻塞读取返回 EOF 并正常退出.
        try? input.fileHandleForWriting.close()
        if running {
            process.terminate()
            process.waitUntilExit()
        }
        try? output.fileHandleForReading.close()
        Log.shared.info("虚拟屏进程已结束: pid=\(process.processIdentifier) displayID=\(displayID)")
    }

    private static func serialNumber(for id: UUID) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt32(byte)
                hash &*= 16_777_619
            }
        }
        return hash
    }

    deinit {
        terminate()
    }
}
