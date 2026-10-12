import Foundation
import Testing
import AttentionControl
import AttentionMCPCore

/// 控制命令 / 响应的编解码与拆包
@Suite("控制协议编解码")
struct ControlCodecTests {
    private let taskId = UUID()
    private let subtaskId = UUID()

    @Test("每个命令都能编解码往返一致")
    func commandRoundTrip() throws {
        let commands: [ControlCommand] = [
            .listTasks,
            .getActiveTask,
            .listCompleted,
            .clearActiveTask,
            .addTask(title: "写方案"),
            .renameTask(id: taskId, title: "新名字"),
            .setActiveTask(id: taskId),
            .sleepTask(id: taskId),
            .wakeTask(id: taskId),
            .finishTask(id: taskId),
            .restoreTask(id: taskId),
            .addSubtask(parentId: taskId, title: "子任务"),
            .renameSubtask(parentId: taskId, subtaskId: subtaskId, title: "改名"),
            .toggleSubtask(parentId: taskId, subtaskId: subtaskId)
        ]

        for command in commands {
            let line = try ControlCodec.encodeLine(command)
            let (lines, remainder) = ControlCodec.splitLines(line)
            #expect(remainder.isEmpty, "编码结果应当是完整的一行")
            #expect(lines.count == 1)

            let decoded = try ControlCodec.decodeLine(lines[0], as: ControlCommand.self)
            #expect(decoded == command, "命令 \(command.name) 往返后不一致")
        }
    }

    @Test("响应能编解码往返一致")
    func responseRoundTrip() throws {
        let responses: [ControlResponse] = [
            .ok,
            .tasks([]),
            .activeTask(nil),
            .completed([]),
            .failure(ControlError(.notFound, "找不到任务"))
        ]

        for response in responses {
            let line = try ControlCodec.encodeLine(response)
            let (lines, _) = ControlCodec.splitLines(line)
            #expect(try ControlCodec.decodeLine(lines[0], as: ControlResponse.self) == response)
        }
    }

    @Test("版本不一致时明确报错，而不是按错误结构解析")
    func versionMismatch() throws {
        // 手造一个版本号为 999 的信封
        let forged = Data(#"{"v":999,"body":{"listTasks":{}}}"#.utf8)
        #expect(throws: ControlCodecError.versionMismatch(peer: 999, mine: ControlCodec.version)) {
            try ControlCodec.decodeLine(forged, as: ControlCommand.self)
        }
    }

    @Test("拆包：半包与粘包由同一个函数覆盖")
    func splitLinesHandlesPartialAndMultiple() {
        var buffer = Data("line1".utf8)
        buffer.append(0x0A)
        buffer.append(Data("li".utf8))

        let (first, remainder) = ControlCodec.splitLines(buffer)
        #expect(first.map { String(decoding: $0, as: UTF8.self) } == ["line1"])
        #expect(String(decoding: remainder, as: UTF8.self) == "li")

        var continued = remainder
        continued.append(Data("ne2".utf8))
        continued.append(0x0A)
        continued.append(Data("line3".utf8))
        continued.append(0x0A)

        let (second, leftover) = ControlCodec.splitLines(continued)
        #expect(second.map { String(decoding: $0, as: UTF8.self) } == ["line2", "line3"])
        #expect(leftover.isEmpty)
    }

    @Test("命令的变更属性划分正确")
    func mutationFlags() {
        #expect(!ControlCommand.listTasks.isMutation)
        #expect(!ControlCommand.getActiveTask.isMutation)
        #expect(!ControlCommand.listCompleted.isMutation)
        #expect(ControlCommand.addTask(title: "x").isMutation)
        #expect(ControlCommand.clearActiveTask.isMutation)
        #expect(ControlCommand.sleepTask(id: taskId).isMutation)
    }
}

// MARK: - MCP 报文处理

/// 测试用的假控制通道：不连 socket，按预设返回
private final class StubControl: ControlSending {
    var responses: [ControlResponse] = []
    private(set) var received: [ControlCommand] = []

    func send(_ command: ControlCommand) throws -> ControlResponse {
        received.append(command)
        return responses.isEmpty ? .ok : responses.removeFirst()
    }
}

@Suite("MCP 报文处理")
struct MCPServerTests {
    private func json(_ line: String) throws -> JSONValue {
        let data = try #require(line.data(using: .utf8))
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    @Test("server/discover 是现代修订版的必需实现")
    func discover() throws {
        let server = MCPServer(control: StubControl())
        let line = try #require(server.handle(#"{"jsonrpc":"2.0","id":1,"method":"server/discover"}"#))
        let result = try json(line)["result"]

        #expect(result?["resultType"]?.stringValue == "complete")
        #expect(result?["supportedVersions"]?.arrayValue?.first?.stringValue == MCPServer.modernProtocolVersion)
        #expect(result?["_meta"]?["io.modelcontextprotocol/serverInfo"]?["name"]?.stringValue == "attention")
    }

    @Test("legacy 客户端走 initialize，版本按请求回声")
    func initialize() throws {
        let server = MCPServer(control: StubControl())
        let request = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#
        let result = try json(try #require(server.handle(request)))["result"]

        #expect(result?["protocolVersion"]?.stringValue == "2024-11-05")
        #expect(result?["serverInfo"]?["name"]?.stringValue == "attention")
    }

    @Test("通知不产生任何输出")
    func notificationProducesNoOutput() {
        let server = MCPServer(control: StubControl())
        #expect(server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test("tools/list 列出全部工具，每个都带 name / description / inputSchema")
    func toolsList() throws {
        let server = MCPServer(control: StubControl())
        let line = try #require(server.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#))
        let tools = try #require(try json(line)["result"]?["tools"]?.arrayValue)

        #expect(tools.count == MCPToolCatalog.tools.count)
        for tool in tools {
            #expect(tool["name"]?.stringValue?.isEmpty == false)
            #expect(tool["description"]?.stringValue?.isEmpty == false)
            #expect(tool["inputSchema"]?["type"]?.stringValue == "object")
        }
    }

    @Test("工具表里不含任何删除类操作")
    func noDestructiveTools() {
        #expect(!MCPToolCatalog.tools.contains { $0.name.lowercased().contains("delete") })
    }

    @Test("tools/call 正常路径会把命令转发出去")
    func toolCallForwardsCommand() throws {
        let stub = StubControl()
        stub.responses = [.tasks([])]
        let server = MCPServer(control: stub)

        _ = server.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_tasks","arguments":{}}}"#)

        #expect(stub.received == [.listTasks])
    }

    @Test("未知工具报协议错误 -32602")
    func unknownTool() throws {
        let server = MCPServer(control: StubControl())
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"delete_task","arguments":{}}}"#
        let error = try json(try #require(server.handle(request)))["error"]

        #expect(error?["code"]?.numberValue == Double(JSONRPCErrorCode.invalidParams))
    }

    @Test("参数不合法属于工具执行错误，以 isError 返回")
    func invalidArguments() throws {
        let server = MCPServer(control: StubControl())
        // 缺 title
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"add_task","arguments":{}}}"#
        let result = try json(try #require(server.handle(request)))["result"]

        #expect(result?["isError"] == .bool(true))
    }

    @Test("未知方法报 -32601，坏 JSON 报 -32700")
    func badMethodAndBadJson() throws {
        let server = MCPServer(control: StubControl())

        let unknown = try json(try #require(server.handle(#"{"jsonrpc":"2.0","id":1,"method":"nope"}"#)))
        #expect(unknown["error"]?["code"]?.numberValue == Double(JSONRPCErrorCode.methodNotFound))

        let broken = try json(try #require(server.handle("{不是 json")))
        #expect(broken["error"]?["code"]?.numberValue == Double(JSONRPCErrorCode.parseError))
    }

    @Test("id 为 null 的请求要回响应，不能被当成通知")
    func nullIdStillResponds() throws {
        let server = MCPServer(control: StubControl())
        let line = try #require(server.handle(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#))
        #expect(try json(line)["id"] == .null)
    }
}
