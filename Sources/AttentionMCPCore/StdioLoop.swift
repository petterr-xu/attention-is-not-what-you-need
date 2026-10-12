import Foundation
import AttentionControl

/// stdio 事件循环：从 stdin 逐行读 JSON-RPC，交给 `MCPServer`，把结果写回 stdout。
///
/// stdout 是与 MCP 客户端之间**唯一**的协议通道——任何非协议输出都会直接破坏它，
/// 所以本进程的日志一律走 stderr。
public final class StdioLoop {
    private let server: MCPServer
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput
    private let queue = DispatchQueue(label: "com.xuwenduan.attention.mcp-stdio")
    private var buffer = Data()

    public init(server: MCPServer) {
        self.server = server
    }

    public func run() {
        input.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else {
                // stdin 关闭 = 客户端要求收工，规范要求服务端及时退出。
                // 退出动作要排到同一条串行队列上：读回调与 consume 不在同一个线程，
                // 直接在这里 exit 可能把刚读到、还没处理的报文连同响应一起丢掉。
                self.queue.async { exit(0) }
                return
            }
            self.queue.async { self.consume(data) }
        }
        dispatchMain()
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        let (lines, remainder) = ControlCodec.splitLines(buffer)
        buffer = remainder

        for line in lines {
            guard let text = String(data: line, encoding: .utf8) else { continue }
            if let response = server.handle(text) {
                write(response)
            }
        }
    }

    private func write(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        try? output.write(contentsOf: data)
    }
}
