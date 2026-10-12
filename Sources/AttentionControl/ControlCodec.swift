import Foundation

public enum ControlCodecError: Error, Equatable {
    /// 对端线协议版本与本端不一致。通常意味着 MCP 配置指向了一个旧版的 attention-mcp，
    /// 明确报错而不是静默按错误的结构解析。
    case versionMismatch(peer: Int, mine: Int)
}

/// 控制通道的线协议：**一行一条消息的 JSON**（NDJSON）。
///
/// 每一行是一个信封 `{"v":<版本>, "body":<消息体>}`。选 NDJSON 是因为两端都是自己的
/// Swift 代码，`JSONEncoder` 不加 `.prettyPrinted` 时输出恒为单行、字符串内的换行会被
/// 转义，所以「消息体不含裸换行」天然成立；调试时还能直接 `nc -U <socket>` 手敲一行。
public enum ControlCodec {
    /// 线协议版本。两端必须一致。
    public static let version = 1

    private struct OutgoingEnvelope<Body: Encodable>: Encodable {
        let v: Int
        let body: Body
    }

    private struct IncomingEnvelope<Body: Decodable>: Decodable {
        let v: Int
        let body: Body
    }

    public static func encodeLine<Body: Encodable>(_ body: Body) throws -> Data {
        var data = try JSONEncoder().encode(OutgoingEnvelope(v: version, body: body))
        data.append(0x0A)
        return data
    }

    public static func decodeLine<Body: Decodable>(_ line: Data, as type: Body.Type) throws -> Body {
        let envelope = try JSONDecoder().decode(IncomingEnvelope<Body>.self, from: line)
        guard envelope.v == version else {
            throw ControlCodecError.versionMismatch(peer: envelope.v, mine: version)
        }
        return envelope.body
    }

    /// 从缓冲里切出所有以 `\n` 结尾的完整行，返回完整行与剩余的不完整尾巴。
    ///
    /// 半包（一次只读到半行）与粘包（一次读到多行）由这一个函数同时覆盖：
    /// 切不出完整行的部分留在 remainder 里，等下次读到再拼。
    public static func splitLines(_ buffer: Data) -> (lines: [Data], remainder: Data) {
        var lines: [Data] = []
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            lines.append(Data(buffer[start..<newline]))
            start = buffer.index(after: newline)
        }
        return (lines, Data(buffer[start...]))
    }
}
