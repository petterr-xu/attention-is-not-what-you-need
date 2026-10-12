import Foundation

public enum ControlClientError: Error, Equatable {
    /// socket 不存在或连不上——app 没在运行
    case appNotRunning
    /// 连上了但没能在超时内拿到完整回复
    case receiveFailed(Int32)
    case malformedResponse(String)
}

/// 控制通道的客户端：连上本地 socket，发一条命令，收一条结果，然后关闭。
///
/// 一次一连接。控制流量是「人工/AI 偶尔调一下」的量级，不值得为复用连接引入额外状态。
public struct ControlClient {
    private let socketURL: URL
    private let timeout: TimeInterval
    private static let maxLineBytes = 1 << 20

    public init(socketURL: URL = ControlSocketPath.defaultURL(),
                timeout: TimeInterval = 5) {
        self.socketURL = socketURL
        self.timeout = timeout
    }

    public func send(_ command: ControlCommand) throws -> ControlResponse {
        var address = try ControlSocketAddress.make(path: socketURL.path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlClientError.appNotRunning }
        defer { close(fd) }
        ControlSocketAddress.disableSigPipe(on: fd)

        // 没有超时的话，app 卡住时桥接进程会永久阻塞
        var timeval = timeval(tv_sec: Int(timeout), tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeval, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeval, socklen_t(MemoryLayout<timeval>.size))

        let connectResult = ControlSocketAddress.withSockaddr(&address) { socketAddress, length in
            connect(fd, socketAddress, length)
        }
        // ENOENT（socket 文件不在）= app 没跑；ECONNREFUSED（文件在但没人听）= 上次崩溃留下的残留
        guard connectResult == 0 else { throw ControlClientError.appNotRunning }

        try writeAll(fd, try ControlCodec.encodeLine(command))
        return try readResponse(fd)
    }

    private func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw ControlClientError.receiveFailed(errno)
                }
                if written == 0 { throw ControlClientError.receiveFailed(0) }
                offset += written
            }
        }
    }

    private func readResponse(_ fd: Int32) throws -> ControlResponse {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                buffer.append(contentsOf: chunk[0..<count])
                let (lines, _) = ControlCodec.splitLines(buffer)
                if let line = lines.first {
                    do {
                        return try ControlCodec.decodeLine(line, as: ControlResponse.self)
                    } catch {
                        throw ControlClientError.malformedResponse(String(describing: error))
                    }
                }
                if buffer.count > Self.maxLineBytes {
                    throw ControlClientError.malformedResponse("回复过长")
                }
            } else if count == 0 {
                throw ControlClientError.malformedResponse("连接在收到完整回复前被关闭")
            } else {
                if errno == EINTR { continue }
                throw ControlClientError.receiveFailed(errno)
            }
        }
    }
}
