import Foundation

/// 控制通道上的命令。
///
/// 用带关联值的穷尽 enum（而不是字符串方法名）是有意的：app 端的 dispatch 对它可以做穷尽
/// `switch`，将来加命令时漏了分支会**直接编译报错**，而不是运行时静默失效。
public enum ControlCommand: Codable, Equatable {
    case listTasks
    case getActiveTask
    case listCompleted
    case addTask(title: String)
    case renameTask(id: UUID, title: String)
    case setActiveTask(id: UUID)
    case clearActiveTask
    case sleepTask(id: UUID)
    case wakeTask(id: UUID)
    case finishTask(id: UUID)
    case restoreTask(id: UUID)
    case addSubtask(parentId: UUID, title: String)
    case renameSubtask(parentId: UUID, subtaskId: UUID, title: String)
    case toggleSubtask(parentId: UUID, subtaskId: UUID)
}

public extension ControlCommand {
    /// 是否为变更操作。安全模式（只读）下只放行非变更命令。
    var isMutation: Bool {
        switch self {
        case .listTasks, .getActiveTask, .listCompleted:
            return false
        case .addTask, .renameTask, .setActiveTask, .clearActiveTask,
             .sleepTask, .wakeTask, .finishTask, .restoreTask,
             .addSubtask, .renameSubtask, .toggleSubtask:
            return true
        }
    }

    /// 面向用户的命令名，用于错误文案
    var name: String {
        switch self {
        case .listTasks: return "list_tasks"
        case .getActiveTask: return "get_active_task"
        case .listCompleted: return "list_completed"
        case .addTask: return "add_task"
        case .renameTask: return "rename_task"
        case .setActiveTask: return "set_active_task"
        case .clearActiveTask: return "clear_active_task"
        case .sleepTask: return "sleep_task"
        case .wakeTask: return "wake_task"
        case .finishTask: return "finish_task"
        case .restoreTask: return "restore_task"
        case .addSubtask: return "add_subtask"
        case .renameSubtask: return "rename_subtask"
        case .toggleSubtask: return "toggle_subtask"
        }
    }
}

/// 控制命令的失败原因
public struct ControlError: Codable, Equatable {
    public enum Kind: String, Codable {
        /// 目标 id 不存在（或不在预期的列表里）
        case notFound
        /// 参数不合法，例如空标题
        case invalidArgument
        /// app 侧的「允许 AI 控制」处于关闭状态
        case aiControlDisabled
        /// app 侧处于安全模式（只读），而该命令是变更操作
        case readOnlyMode
        /// 线协议解析失败
        case badRequest
    }

    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    public static func aiDisabled() -> ControlError {
        ControlError(.aiControlDisabled,
                     "AI 控制未开启。请在菜单栏图标的右键菜单里选择「允许 AI 控制」，"
                     + "并切到「开放（读写）」。")
    }

    public static func readOnly(_ command: String) -> ControlError {
        ControlError(.readOnlyMode,
                     "当前是「安全（只读）」模式，\(command) 属于变更操作，已被拒绝。"
                     + "如需让 AI 修改待办，请在右键菜单里切到「开放（读写）」。")
    }
}

/// 控制命令的执行结果
public enum ControlResponse: Codable, Equatable {
    /// 成功且无返回值
    case ok
    /// 待办列表
    case tasks([TaskDTO])
    /// 当前在做任务；没有当前任务时 associated value 为 nil
    case activeTask(TaskDTO?)
    /// 已完成列表
    case completed([CompletedTaskDTO])
    /// 失败
    case failure(ControlError)
}
