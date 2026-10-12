import Foundation
import AttentionControl

/// JSON-RPC 2.0 标准错误码
public enum JSONRPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
}

/// 客户端请求。`id` 缺失即为通知。
public struct JSONRPCRequest: Decodable {
    public let jsonrpc: String
    public let id: JSONValue?
    public let method: String
    public let params: JSONValue?

    /// `id` 是否出现在报文里。
    ///
    /// 必须单独记，不能只看 `id != nil`：JSON-RPC 里「`id: null`」和「没有 `id`」是两回事——
    /// 前者是请求（要回一个 id 为 null 的响应），后者是通知（不产生响应）。
    public let hasID: Bool

    private enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        hasID = container.contains(.id)
        id = try container.decodeIfPresent(JSONValue.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
    }

    public var isNotification: Bool { !hasID }

    /// 现代修订版（2026-07-28 起）的请求都带 `_meta` 里的协议版本；legacy 请求没有。
    public var isModern: Bool {
        params?["_meta"]?["io.modelcontextprotocol/protocolVersion"] != nil
    }
}

/// 按 JSON-RPC 2.0 组装响应
public enum JSONRPCResponse {
    public static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
    }

    public static func error(id: JSONValue?, code: Int, message: String) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id ?? .null,
            "error": .object([
                "code": .number(Double(code)),
                "message": .string(message)
            ])
        ])
    }
}
