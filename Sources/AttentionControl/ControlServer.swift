import Foundation

/// 本地控制通道的服务端：监听 Unix domain socket，把收到的命令交给注入的 handler 执行。
///
/// **线程模型**：accept / 读 / 写都在自己的串行队列上；命令的执行 hop 到 `handlerQueue`。
/// app 传 `.main`——`AppState` 的所有变更必须在主线程（它是 SwiftUI 的 `@Published` 源，
/// 且与两个 Timer 的写盘存在竞争）。测试则传自己的串行队列，避免依赖主线程 runloop。
public final class ControlServer {
    public typealias Handler = (ControlCommand) -> ControlResponse

    /// 单条消息的字节上限。超过就直接断开——防止对端（或 bug）把内存吃干。
    private static let maxLineBytes = 1 << 20

    private let socketURL: URL
    private let handlerQueue: DispatchQueue
    private let handler: Handler
    /// 串行队列：连接表与每个连接的读写都在这上面，天然互斥
    private let queue = DispatchQueue(label: "com.xuwenduan.attention.control-server")

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]

    public init(socketURL: URL = ControlSocketPath.defaultURL(),
                handlerQueue: DispatchQueue = .main,
                handler: @escaping Handler) {
        self.socketURL = socketURL
        self.handlerQueue = handlerQueue
        self.handler = handler
    }

    public func start() throws {
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])

        // 陈旧 socket：app 被 `pkill Attention`（SIGTERM）时走不到清理逻辑，socket 文件会留在盘上。
        // 统一在 bind 前先删（忽略 ENOENT），正常退出与崩溃退出都由这一条兜底，不需要信号处理器。
        unlink(socketURL.path)

        var address = try ControlSocketAddress.make(path: socketURL.path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlSocketError.createFailed(errno) }
        ControlSocketAddress.disableSigPipe(on: fd)

        let bindResult = ControlSocketAddress.withSockaddr(&address) { socketAddress, length in
            bind(fd, socketAddress, length)
        }
        guard bindResult == 0 else {
            let code = errno
            close(fd)
            throw ControlSocketError.bindFailed(code)
        }

        // bind 建文件用的是 `0666 & ~umask`，默认会得到 0644 —— 同机其他用户可连。
        // 必须显式收紧到 0600：这条连同目录的 0700 一起，是「只限本机同用户」的唯一保障。
        chmod(socketURL.path, 0o600)

        guard listen(fd, 8) == 0 else {
            let code = errno
            close(fd)
            unlink(socketURL.path)
            throw ControlSocketError.listenFailed(code)
        }

        // 非阻塞 accept：配合读源一次把待处理的连接accept 干净
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPendingConnections() }
        source.setCancelHandler { [weak self] in
            guard let self, self.listenFD >= 0 else { return }
            close(self.listenFD)
            self.listenFD = -1
        }
        acceptSource = source
        source.resume()
    }

    public func stop() {
        queue.sync {
            for connection in connections.values { connection.cancel() }
            connections.removeAll()
            acceptSource?.cancel()
            acceptSource = nil
            unlink(socketURL.path)
        }
    }

    private func acceptPendingConnections() {
        while true {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                return   // EAGAIN/EWOULDBLOCK 表示本轮已接完，其它错误也无需继续
            }
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            ControlSocketAddress.disableSigPipe(on: fd)

            let connection = Connection(fd: fd,
                                        queue: queue,
                                        handlerQueue: handlerQueue,
                                        handler: handler,
                                        maxLineBytes: Self.maxLineBytes) { [weak self] closedFD in
                self?.connections[closedFD] = nil
            }
            connections[fd] = connection
            connection.start()
        }
    }
}

// MARK: - 单条连接

/// 一个已接受的连接。只做三件事：按行拆包、把命令交给 handlerQueue、把结果写回。
private final class Connection {
    private let fd: Int32
    private let queue: DispatchQueue
    private let handlerQueue: DispatchQueue
    private let handler: (ControlCommand) -> ControlResponse
    private let maxLineBytes: Int
    private let onClose: (Int32) -> Void

    private var source: DispatchSourceRead?
    private var buffer = Data()

    init(fd: Int32,
         queue: DispatchQueue,
         handlerQueue: DispatchQueue,
         handler: @escaping (ControlCommand) -> ControlResponse,
         maxLineBytes: Int,
         onClose: @escaping (Int32) -> Void) {
        self.fd = fd
        self.queue = queue
        self.handlerQueue = handlerQueue
        self.handler = handler
        self.maxLineBytes = maxLineBytes
        self.onClose = onClose
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            close(self.fd)          // DispatchSource 不会替我们关 fd
            self.onClose(self.fd)
        }
        self.source = source
        source.resume()
    }

    func cancel() {
        source?.cancel()
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        let count = read(fd, &chunk, chunk.count)
        if count > 0 {
            buffer.append(contentsOf: chunk[0..<count])
            drain()
        } else if count == 0 {
            source?.cancel()        // 对端关闭
        } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
            source?.cancel()
        }
    }

    private func drain() {
        let (lines, remainder) = ControlCodec.splitLines(buffer)
        buffer = remainder

        // 迟迟等不到换行说明对端在灌垃圾，直接断开
        if buffer.count > maxLineBytes {
            source?.cancel()
            return
        }

        for line in lines {
            guard let command = try? ControlCodec.decodeLine(line, as: ControlCommand.self) else {
                writeResponse(.failure(ControlError(.badRequest, "无法解析的命令")))
                continue
            }
            // AppState 的变更必须在主线程，所以这里必须 hop
            handlerQueue.async { [weak self] in
                guard let self else { return }
                let response = self.handler(command)
                self.queue.async { self.writeResponse(response) }
            }
        }
    }

    private func writeResponse(_ response: ControlResponse) {
        guard let data = try? ControlCodec.encodeLine(response) else { return }
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    source?.cancel()
                    return
                }
                if written == 0 {
                    source?.cancel()
                    return
                }
                offset += written
            }
        }
    }
}
