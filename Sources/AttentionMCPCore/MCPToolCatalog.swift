import Foundation
import AttentionControl

public enum ToolCallError: Error, Equatable {
    /// 工具名不存在
    case unknownTool(String)
    /// 参数不合法（缺失、类型不对、不是合法 id）
    case invalidArguments(String)

    public var message: String {
        switch self {
        case .unknownTool(let name):
            return "未知工具：\(name)"
        case .invalidArguments(let detail):
            return detail
        }
    }
}

/// 一个 MCP 工具的定义。
///
/// 把「工具元信息」和「参数 → 控制命令的构造」放在同一条记录里，两者不会各自漂移。
public struct MCPTool {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    let build: (JSONValue?) throws -> ControlCommand

    /// `tools/list` 里该工具的样子
    public var jsonValue: JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema
        ])
    }
}

public enum MCPToolCatalog {
    /// 暴露给 AI 的全部工具。
    ///
    /// 刻意**不含任何删除操作**（delete_task / delete_subtask）——删除不可逆，不给模型。
    public static let tools: [MCPTool] = [
        MCPTool(name: "list_tasks",
                description: "列出全部待办任务，含状态（active 正在做 / suspended 挂起 / sleeping 睡眠）、"
                    + "创建时间、时长与子任务。睡眠任务沉在列表末尾且不计时。",
                inputSchema: noArguments,
                build: { _ in .listTasks }),

        MCPTool(name: "get_active_task",
                description: "查看当前正在做的任务，以及本次会话已进行的时长。没有当前任务时返回 null。",
                inputSchema: noArguments,
                build: { _ in .getActiveTask }),

        MCPTool(name: "list_completed",
                description: "列出已完成的任务，含结束时间与是否由「跨周自动结束」产生。",
                inputSchema: noArguments,
                build: { _ in .listCompleted }),

        MCPTool(name: "add_task",
                description: "新建一个待办任务。",
                inputSchema: schema(["title": stringProperty("任务标题")], required: ["title"]),
                build: { args in .addTask(title: try string(args, "title", tool: "add_task")) }),

        MCPTool(name: "rename_task",
                description: "重命名一个待办任务。",
                inputSchema: schema(["id": stringProperty("任务 id，来自 list_tasks"),
                                     "title": stringProperty("新标题")],
                                    required: ["id", "title"]),
                build: { args in
                    .renameTask(id: try uuid(args, "id", tool: "rename_task"),
                                title: try string(args, "title", tool: "rename_task"))
                }),

        MCPTool(name: "set_active_task",
                description: "把某个任务设为「当前在做」，原来的当前任务会自动转为挂起。"
                    + "若该任务已经是当前任务则不做任何改变。",
                inputSchema: schema(["id": stringProperty("任务 id")], required: ["id"]),
                build: { args in .setActiveTask(id: try uuid(args, "id", tool: "set_active_task")) }),

        MCPTool(name: "clear_active_task",
                description: "取消当前任务，使没有任何任务处于「正在做」。",
                inputSchema: noArguments,
                build: { _ in .clearActiveTask }),

        MCPTool(name: "sleep_task",
                description: "让任务进入睡眠：置灰并沉到列表最下方，不计时、不会被跨周自动结束。",
                inputSchema: schema(["id": stringProperty("任务 id")], required: ["id"]),
                build: { args in .sleepTask(id: try uuid(args, "id", tool: "sleep_task")) }),

        MCPTool(name: "wake_task",
                description: "唤醒睡眠中的任务：回到挂起状态，并按列表规则排到对应位置。",
                inputSchema: schema(["id": stringProperty("任务 id")], required: ["id"]),
                build: { args in .wakeTask(id: try uuid(args, "id", tool: "wake_task")) }),

        MCPTool(name: "finish_task",
                description: "结束任务，把它移入已完成列表。",
                inputSchema: schema(["id": stringProperty("任务 id")], required: ["id"]),
                build: { args in .finishTask(id: try uuid(args, "id", tool: "finish_task")) }),

        MCPTool(name: "restore_task",
                description: "把已完成的任务放回待办列表。id 来自 list_completed。",
                inputSchema: schema(["id": stringProperty("已完成任务的 id")], required: ["id"]),
                build: { args in .restoreTask(id: try uuid(args, "id", tool: "restore_task")) }),

        MCPTool(name: "add_subtask",
                description: "给指定任务添加一个子任务。",
                inputSchema: schema(["parentId": stringProperty("父任务 id"),
                                     "title": stringProperty("子任务标题")],
                                    required: ["parentId", "title"]),
                build: { args in
                    .addSubtask(parentId: try uuid(args, "parentId", tool: "add_subtask"),
                                title: try string(args, "title", tool: "add_subtask"))
                }),

        MCPTool(name: "rename_subtask",
                description: "重命名子任务。",
                inputSchema: schema(["parentId": stringProperty("父任务 id"),
                                     "subtaskId": stringProperty("子任务 id"),
                                     "title": stringProperty("新标题")],
                                    required: ["parentId", "subtaskId", "title"]),
                build: { args in
                    .renameSubtask(parentId: try uuid(args, "parentId", tool: "rename_subtask"),
                                   subtaskId: try uuid(args, "subtaskId", tool: "rename_subtask"),
                                   title: try string(args, "title", tool: "rename_subtask"))
                }),

        MCPTool(name: "toggle_subtask",
                description: "勾选 / 取消勾选子任务。",
                inputSchema: schema(["parentId": stringProperty("父任务 id"),
                                     "subtaskId": stringProperty("子任务 id")],
                                    required: ["parentId", "subtaskId"]),
                build: { args in
                    .toggleSubtask(parentId: try uuid(args, "parentId", tool: "toggle_subtask"),
                                   subtaskId: try uuid(args, "subtaskId", tool: "toggle_subtask"))
                })
    ]

    public static func tool(named name: String) -> MCPTool? {
        tools.first { $0.name == name }
    }

    public static func command(name: String, arguments: JSONValue?) throws -> ControlCommand {
        guard let tool = tool(named: name) else {
            throw ToolCallError.unknownTool(name)
        }
        return try tool.build(arguments)
    }

    // MARK: - 参数提取

    private static func string(_ arguments: JSONValue?, _ key: String, tool: String) throws -> String {
        guard let value = arguments?[key]?.stringValue else {
            throw ToolCallError.invalidArguments("\(tool) 缺少参数 \(key)（应为字符串）")
        }
        return value
    }

    private static func uuid(_ arguments: JSONValue?, _ key: String, tool: String) throws -> UUID {
        let raw = try string(arguments, key, tool: tool)
        guard let value = UUID(uuidString: raw) else {
            throw ToolCallError.invalidArguments("\(tool) 的参数 \(key) 不是合法的 id：\(raw)")
        }
        return value
    }

    // MARK: - 输入 schema

    /// 无参数工具用这个。规范推荐显式写 `additionalProperties: false`。
    private static let noArguments: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false)
    ])

    private static func stringProperty(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private static func schema(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map { .string($0) }),
            "additionalProperties": .bool(false)
        ])
    }
}
