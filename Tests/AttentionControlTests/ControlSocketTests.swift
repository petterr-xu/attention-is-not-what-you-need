import Foundation
import Testing
import AttentionControl

/// 控制通道 socket 层的端到端测试。
///
/// 起真的 `ControlServer`、用真的 `ControlClient` 连上去，覆盖 POSIX 那些容易写错的地方：
/// 权限、残留 socket、以及「app 没跑」时的错误语义。
@Suite("控制通道 socket")
struct ControlSocketTests {
    /// 名字刻意取短：临时目录前缀已经有 48 字节，而 socket 路径上限是 103 字节
    /// （`sun_path` 含结尾 NUL 共 104），拼完整 UUID 会直接顶到上限。
    private func temporarySocketURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("at-\(UUID().uuidString.prefix(8)).sock")
    }

    private func makeServer(at url: URL,
                            handler: @escaping ControlServer.Handler) -> ControlServer {
        ControlServer(socketURL: url,
                      handlerQueue: DispatchQueue(label: "attention.test.handler"),
                      handler: handler)
    }

    @Test("客户端与服务器端到端收发")
    func endToEnd() throws {
        let url = temporarySocketURL()
        let server = makeServer(at: url) { command in
            command == .listTasks ? .tasks([]) : .ok
        }
        defer { server.stop(); unlink(url.path) }
        try server.start()

        let client = ControlClient(socketURL: url)
        #expect(try client.send(.listTasks) == .tasks([]))
        #expect(try client.send(.clearActiveTask) == .ok)
    }

    @Test("socket 文件权限被收紧到 0600")
    func socketFileIsOwnerOnly() throws {
        let url = temporarySocketURL()
        let server = makeServer(at: url) { _ in .ok }
        defer { server.stop(); unlink(url.path) }
        try server.start()

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        // bind 建文件按 0666 & ~umask，不显式 chmod 会得到 0644，同机其他用户就能连
        #expect(permissions.intValue == 0o600)
    }

    @Test("上次崩溃留下的 socket 文件会被清掉再重新 bind")
    func staleSocketFileIsReplaced() throws {
        let url = temporarySocketURL()
        defer { unlink(url.path) }

        // 模拟 pkill 之后残留的文件
        try Data("stale".utf8).write(to: url)

        let server = makeServer(at: url) { _ in .ok }
        defer { server.stop() }
        try server.start()   // 不应抛错

        let client = ControlClient(socketURL: url)
        #expect(try client.send(.clearActiveTask) == .ok)
    }

    @Test("socket 不存在时明确报「app 未运行」")
    func clientReportsAppNotRunning() {
        let client = ControlClient(socketURL: temporarySocketURL())
        #expect(throws: ControlClientError.appNotRunning) {
            _ = try client.send(.listTasks)
        }
    }

    @Test("handlerQueue 可注入：命令确实在指定队列上执行")
    func handlerRunsOnInjectedQueue() throws {
        let url = temporarySocketURL()
        let key = DispatchSpecificKey<String>()
        let queue = DispatchQueue(label: "attention.test.injected")
        queue.setSpecific(key: key, value: "injected")

        let server = ControlServer(socketURL: url, handlerQueue: queue) { _ in
            // send() 会一直阻塞到 handler 返回，所以这条断言一定在回复写出之前执行
            #expect(DispatchQueue.getSpecific(key: key) == "injected")
            return .ok
        }
        defer { server.stop(); unlink(url.path) }
        try server.start()

        #expect(try ControlClient(socketURL: url).send(.clearActiveTask) == .ok)
    }
}
