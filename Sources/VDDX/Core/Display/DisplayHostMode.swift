import CoreGraphics
import CVirtualDisplayBridge
import Foundation

/// 子进程模式: 创建并持有一块虚拟屏, 直到 stdin 关闭或进程被终止.
///
/// 进程退出时系统会回收虚拟屏, 所以这是删除虚拟屏的唯一可靠方式.
enum DisplayHostMode {
    static func run(arguments: [String]) -> Never {
        guard arguments.count >= 3, let data = arguments[2].data(using: .utf8) else {
            respond(DisplayHost.Response(displayID: nil, error: "缺少 host 参数"))
            exit(2)
        }
        guard let request = try? JSONDecoder().decode(DisplayHost.Request.self, from: data) else {
            respond(DisplayHost.Response(displayID: nil, error: "host 参数无法解析"))
            exit(2)
        }

        var error = VDXError()
        var modes = [
            VDXDisplayMode(
                width: UInt32(request.logicalWidth),
                height: UInt32(request.logicalHeight),
                refresh_rate: request.refreshRate
            )
        ]
        let handle: VDXDisplayHandle? = request.name.withCString { name in
            modes.withUnsafeBufferPointer { buffer in
                VDXDisplayCreate(
                    name,
                    UInt32(request.maxPixelsWide),
                    UInt32(request.maxPixelsHigh),
                    request.sizeMillimetersWide,
                    request.sizeMillimetersHigh,
                    request.serial,
                    request.product,
                    request.vendor,
                    buffer.baseAddress,
                    buffer.count,
                    request.hiDPI ? 1 : 0,
                    &error
                )
            }
        }
        guard let handle else {
            let message = withUnsafeBytes(of: &error.message) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            respond(DisplayHost.Response(displayID: nil, error: message.isEmpty ? "创建失败" : message))
            exit(3)
        }

        let displayID = VDXDisplayGetID(handle)
        guard displayID != 0 else {
            respond(DisplayHost.Response(displayID: nil, error: "displayID 无效"))
            exit(4)
        }
        respond(DisplayHost.Response(displayID: displayID, error: nil))

        // 阻塞等待父进程关闭 stdin. 收到 EOF 后退出, 系统随之回收虚拟屏.
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let count = read(STDIN_FILENO, &buffer, buffer.count)
            if count > 0 { continue }
            if count == 0 { break }
            if errno == EINTR { continue }
            break
        }
        _ = handle
        exit(0)
    }

    private static func respond(_ response: DisplayHost.Response) {
        guard let data = try? JSONEncoder().encode(response),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        print(line)
        fflush(stdout)
    }
}
