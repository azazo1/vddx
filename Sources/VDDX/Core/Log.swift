import Foundation

enum LogLevel: Int, Comparable, CaseIterable {
    case trace = 0
    case debug = 1
    case info = 2
    case warn = 3
    case error = 4

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }

    init?(name: String) {
        switch name.lowercased() {
        case "trace": self = .trace
        case "debug": self = .debug
        case "info": self = .info
        case "warn", "warning": self = .warn
        case "error": self = .error
        default: return nil
        }
    }
}

/// 进程级日志.
///
/// 同时写入标准错误与文件. 文件按天与大小轮转, 默认保留最近 5 个文件.
/// 日志级别可在运行时通过设置调整.
final class Log: @unchecked Sendable {
    static let shared = Log()

    private let lock = NSLock()
    private var level: LogLevel = .info
    private var mirrorToStderr = true
    private var fileWriter: RotatingFileWriter?
    private let formatter: DateFormatter

    private init() {
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
    }

    func configure(level: LogLevel, fileURL: URL?, mirrorToStderr: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        self.level = level
        self.mirrorToStderr = mirrorToStderr
        if let fileURL {
            fileWriter = RotatingFileWriter(baseURL: fileURL)
        }
    }

    func setLevel(_ level: LogLevel) {
        lock.lock()
        defer { lock.unlock() }
        self.level = level
    }

    func currentLevel() -> LogLevel {
        lock.lock()
        defer { lock.unlock() }
        return level
    }

    func trace(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        write(.trace, message(), file: file, line: line)
    }

    func debug(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        write(.debug, message(), file: file, line: line)
    }

    func info(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        write(.info, message(), file: file, line: line)
    }

    func warn(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        write(.warn, message(), file: file, line: line)
    }

    func error(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        write(.error, message(), file: file, line: line)
    }

    /// 记录阶段耗时, 便于判断流程是否卡住.
    func measure<T>(_ stage: String, _ body: () throws -> T) rethrows -> T {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            debug("\(stage) 耗时 \(String(format: "%.1f", elapsedMS)) ms")
        }
        return try body()
    }

    private func write(_ level: LogLevel, _ message: String, file: StaticString, line: UInt) {
        lock.lock()
        defer { lock.unlock() }
        guard level >= self.level else { return }

        let timestamp = formatter.string(from: Date())
        let source = (String(describing: file) as NSString).lastPathComponent
        let lineText = "\(timestamp) [\(level.label)] [\(source):\(line)] \(message)"

        if mirrorToStderr {
            FileHandle.standardError.write(Data((lineText + "\n").utf8))
        }
        fileWriter?.append(lineText + "\n")
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        fileWriter?.flush()
    }
}

/// 按天与单文件大小轮转的文本写入器.
private final class RotatingFileWriter {
    private let baseURL: URL
    private let maxBytes: UInt64
    private let maxFiles: Int
    private var handle: FileHandle?
    private var currentSize: UInt64 = 0
    private var currentDay: String = ""
    private var rotationIndex = 0

    init(baseURL: URL, maxBytes: UInt64 = 10 * 1024 * 1024, maxFiles: Int = 5) {
        self.baseURL = baseURL
        self.maxBytes = maxBytes
        self.maxFiles = maxFiles
    }

    func append(_ text: String) {
        let day = Self.dayString()
        if day != currentDay || currentSize >= maxBytes {
            rotate(day: day, force: currentSize >= maxBytes)
        }
        guard let data = text.data(using: .utf8) else { return }
        handle?.seekToEndOfFile()
        handle?.write(data)
        currentSize += UInt64(data.count)
    }

    func flush() {
        handle?.synchronizeFile()
    }

    private func rotate(day: String, force: Bool) {
        if day == currentDay && !force {
            return
        }
        handle?.closeFile()
        handle = nil
        currentDay = day
        var candidate = String(format: "vddx-%@", day)
        if force {
            rotationIndex += 1
            candidate += "-\(rotationIndex)"
        }
        let url = baseURL.deletingLastPathComponent().appendingPathComponent(candidate + ".log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        if let newHandle = try? FileHandle(forWritingTo: url) {
            handle = newHandle
            currentSize = newHandle.seekToEndOfFile()
        } else {
            handle = nil
            currentSize = 0
        }
        pruneOldFiles()
    }

    private func pruneOldFiles() {
        let directory = baseURL.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let logs = names
            .filter { $0.hasPrefix("vddx-") && $0.hasSuffix(".log") }
            .map { directory.appendingPathComponent($0) }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
        for url in logs.dropFirst(maxFiles) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func dayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
