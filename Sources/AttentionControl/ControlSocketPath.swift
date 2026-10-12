import Foundation

/// 控制通道的位置约定。app 端与桥接端共用，避免两边写岔。
public enum ControlSocketPath {
    /// 控制通道 socket 的默认路径。
    ///
    /// 放在 Application Support 的私有目录下，配合 socket 文件的 0600 权限，
    /// 天然只限本机同一用户的进程能连。
    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        return base.appendingPathComponent("Attention", isDirectory: true)
                   .appendingPathComponent("control.sock")
    }

    /// `sockaddr_un.sun_path` 的容量。macOS 上是 104 字节，超长会被静默截断，
    /// 所以两端都要在 bind / connect 前检查。
    public static let maxPathBytes = 104
}
