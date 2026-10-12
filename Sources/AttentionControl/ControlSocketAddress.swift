import Foundation

public enum ControlSocketError: Error {
    /// socket 路径超过 `sockaddr_un.sun_path` 容量，会被系统静默截断
    case pathTooLong(String)
    case createFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
}

/// 把路径装进 `sockaddr_un`。bind 与 connect 两端共用一份，避免各写各的。
enum ControlSocketAddress {
    static func make(path: String) throws -> sockaddr_un {
        guard path.utf8.count < ControlSocketPath.maxPathBytes else {
            throw ControlSocketError.pathTooLong(path)
        }

        var address = sockaddr_un()
        // BSD 下 sun_len 必须显式设置，否则 bind 可能失败
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)

        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                path.withCString { source in
                    _ = strlcpy(destination, source, capacity)
                }
            }
        }
        return address
    }

    /// 以 `sockaddr` 指针执行 body —— bind / connect 都需要这个转换
    static func withSockaddr<T>(_ address: inout sockaddr_un,
                                _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) rethrows -> T {
        try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                try body(socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    /// 关掉该 fd 上的 SIGPIPE。否则对端提前关闭时，写入会直接杀掉进程（app 与桥接进程都用）。
    static func disableSigPipe(on fd: Int32) {
        var value: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE,
                       &value, socklen_t(MemoryLayout<Int32>.size))
    }
}
