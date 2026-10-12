import Foundation
import AttentionControl

/// 把控制命令发出去的最小接口。抽成协议是为了测试能塞 stub，不必连真 socket。
public protocol ControlSending {
    func send(_ command: ControlCommand) throws -> ControlResponse
}

extension ControlClient: ControlSending {}

/// MCP 服务端的协议处理。
///
/// `handle(_:)` 是**纯字符串进、字符串出**的，内部没有任何 I/O（socket 通过注入的
/// `ControlSending` 访问），所以可以直接喂报文单测。
public final class MCPServer {
    /// 现代修订版（2026-07-28 起）取消了 `initialize` 握手：版本、身份、能力改由每个请求的
    /// `_meta` 携带，并要求服务端实现 `server/discover`。
    ///
    /// 这里做成 **dual-era**：现代发现与 legacy 握手都支持——legacy-only 与 modern-only
    /// 的客户端都能用。客户端连 stdio server 时会先探 `server/discover`，拿到「非现代错误」
    /// 才回退到 `initialize`，两条路都通。
    public static let modernProtocolVersion = "2026-07-28"
    /// legacy 客户端没带版本时的兜底
    public static let fallbackProtocolVersion = "2025-06-18"

    private static let serverName = "attention"
    private static let serverVersion = "1.0.0"

    private static let instructions = """
        Attention 是本机的一个待办应用。任务有三种状态：active（正在做）、suspended（挂起）、\
        sleeping（睡眠——沉在列表最底部、不计时、不会被跨周自动结束）。\
        所有操作都需要先 list_tasks 拿到任务的 id。\
        读写权限由用户在 Attention 应用里控制：关闭时任何调用都会失败；安全模式只允许读取。
        """

    private let control: ControlSending

    public init(control: ControlSending) {
        self.control = control
    }

    /// 处理一行输入，返回要写到 stdout 的一行；返回 nil 表示这是通知，不产生输出。
    public func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data),
              request.jsonrpc == "2.0" else {
            return encode(JSONRPCResponse.error(id: nil,
                                                code: JSONRPCErrorCode.parseError,
                                                message: "Parse error"))
        }
        guard !request.isNotification else { return nil }

        let id = request.id ?? .null
        switch request.method {
        case "server/discover":
            return encode(JSONRPCResponse.result(id: id, discoverResult()))
        case "initialize":
            return encode(JSONRPCResponse.result(id: id, initializeResult(request: request)))
        case "ping":
            return encode(JSONRPCResponse.result(id: id, .object([:])))
        case "tools/list":
            return encode(JSONRPCResponse.result(id: id, toolsListResult(modern: request.isModern)))
        case "tools/call":
            return handleToolCall(request: request, id: id)
        default:
            return encode(JSONRPCResponse.error(id: id,
                                                code: JSONRPCErrorCode.methodNotFound,
                                                message: "Method not found: \(request.method)"))
        }
    }

    // MARK: - 能力与身份

    private func serverInfo() -> JSONValue {
        .object(["name": .string(Self.serverName), "version": .string(Self.serverVersion)])
    }

    private func capabilities() -> JSONValue {
        // 只做 tools；不提供 resources / prompts
        .object(["tools": .object([:])])
    }

    // MARK: - 各方法的结果

    private func discoverResult() -> JSONValue {
        .object([
            "resultType": .string("complete"),
            "supportedVersions": .array([.string(Self.modernProtocolVersion)]),
            "capabilities": capabilities(),
            "_meta": .object(["io.modelcontextprotocol/serverInfo": serverInfo()]),
            "instructions": .string(Self.instructions)
        ])
    }

    private func initializeResult(request: JSONRPCRequest) -> JSONValue {
        // legacy：把客户端请求的版本原样回声，避免客户端因版本不匹配而拒绝
        let requested = request.params?["protocolVersion"]?.stringValue
        return .object([
            "protocolVersion": .string(requested ?? Self.fallbackProtocolVersion),
            "capabilities": capabilities(),
            "serverInfo": serverInfo(),
            "instructions": .string(Self.instructions)
        ])
    }

    private func toolsListResult(modern: Bool) -> JSONValue {
        var result: [String: JSONValue] = [
            "tools": .array(MCPToolCatalog.tools.map(\.jsonValue))
        ]
        if modern { result["resultType"] = .string("complete") }
        return .object(result)
    }

    private func handleToolCall(request: JSONRPCRequest, id: JSONValue) -> String? {
        guard let name = request.params?["name"]?.stringValue else {
            return encode(JSONRPCResponse.error(id: id,
                                                code: JSONRPCErrorCode.invalidParams,
                                                message: "tools/call 缺少 name"))
        }
        let arguments = request.params?["arguments"]
        let modern = request.isModern

        let command: ControlCommand
        do {
            command = try MCPToolCatalog.command(name: name, arguments: arguments)
        } catch let ToolCallError.unknownTool(unknown) {
            // 工具名不存在属于「协议错误」，模型改参数也救不回来
            return encode(JSONRPCResponse.error(id: id,
                                                code: JSONRPCErrorCode.invalidParams,
                                                message: "Unknown tool: \(unknown)"))
        } catch {
            // 参数问题属于「工具执行错误」，以 isError 结果返回，模型能据此自我修正
            let message = (error as? ToolCallError)?.message ?? "\(error)"
            return encode(JSONRPCResponse.result(id: id,
                                                 errorResult(message: message, modern: modern)))
        }

        do {
            let response = try control.send(command)
            return encode(JSONRPCResponse.result(id: id, result(from: response, modern: modern)))
        } catch let error as ControlClientError {
            return encode(JSONRPCResponse.result(id: id,
                                                 errorResult(message: Self.describe(error), modern: modern)))
        } catch {
            return encode(JSONRPCResponse.result(id: id,
                                                 errorResult(message: "\(error)", modern: modern)))
        }
    }

    private func result(from response: ControlResponse, modern: Bool) -> JSONValue {
        switch response {
        case .ok:
            return toolResult(payload: .object(["ok": .bool(true)]), modern: modern)
        case .tasks(let tasks):
            return toolResult(payload: jsonValue(tasks), modern: modern)
        case .activeTask(let task):
            return toolResult(payload: task.map(jsonValue) ?? .null, modern: modern)
        case .completed(let tasks):
            return toolResult(payload: jsonValue(tasks), modern: modern)
        case .failure(let error):
            return errorResult(message: error.message, modern: modern)
        }
    }

    // MARK: - 结果组装

    private func toolResult(payload: JSONValue, modern: Bool) -> JSONValue {
        var result: [String: JSONValue] = [
            // 规范建议：返回结构化内容时，同时把序列化后的 JSON 放进 text，兼容只看 text 的客户端
            "content": .array([.object([
                "type": .string("text"),
                "text": .string(serialize(payload))
            ])]),
            "structuredContent": payload,
            "isError": .bool(false)
        ]
        if modern { result["resultType"] = .string("complete") }
        return .object(result)
    }

    private func errorResult(message: String, modern: Bool) -> JSONValue {
        var result: [String: JSONValue] = [
            "content": .array([.object([
                "type": .string("text"),
                "text": .string(message)
            ])]),
            "isError": .bool(true)
        ]
        if modern { result["resultType"] = .string("complete") }
        return .object(result)
    }

    private func encode(_ value: JSONValue) -> String {
        serialize(value)
    }

    /// 编码不可能失败（JSONValue 全类型可编码），失败时退化成空对象而不是让调用方处理 nil
    private func serialize(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func jsonValue<T: Encodable>(_ value: T) -> JSONValue {
        guard let data = try? JSONEncoder().encode(value),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .null
        }
        return decoded
    }

    private static func describe(_ error: ControlClientError) -> String {
        switch error {
        case .appNotRunning:
            return "Attention 未在运行。请先打开 Attention（屏幕顶部菜单栏的清单图标），再重试。"
        case .receiveFailed:
            return "Attention 未在超时内响应，请确认应用是否卡住。"
        case .malformedResponse(let detail):
            return "Attention 返回了无法解析的响应（\(detail)）。"
                + "若刚升级过 Attention，请重新复制一次 MCP 配置，确认指向新版 helper。"
        }
    }
}
