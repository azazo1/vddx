import Foundation

/// 基于数据目录的单实例锁.
///
/// 锁文件放在数据目录内, 因此 `just debug` 的隔离实例与正式实例可以并行运行.
/// 进程退出时文件描述符关闭, 锁自动释放.
final class SingleInstanceLock {
    private let fd: Int32
    private let path: URL

    init?(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(".vddx.lock")
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            Log.shared.error("无法打开单实例锁文件: \(url.path)")
            return nil
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            Log.shared.info("数据目录已被其他实例占用: \(directory.path)")
            return nil
        }
        ftruncate(descriptor, 0)
        let text = "\(ProcessInfo.processInfo.processIdentifier)\n"
        _ = text.withCString { pointer in
            write(descriptor, pointer, strlen(pointer))
        }
        self.fd = descriptor
        self.path = url
        Log.shared.debug("已获取单实例锁: \(url.path)")
    }

    deinit {
        close(fd)
    }
}
