import Foundation

/// 子任务，面向外部调用者的表示
public struct SubtaskDTO: Codable, Equatable {
    public let id: String
    public let title: String
    public let isDone: Bool

    public init(id: String, title: String, isDone: Bool) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

/// 待办任务，面向外部调用者的表示。
///
/// 时间刻意用 **ISO8601 字符串 + 计算好的秒数**，而不是直接编码 `Date`：
/// `JSONEncoder` 对 Date 的默认编码是「2001 参考秒」，模型看到的是一个无意义的大数。
public struct TaskDTO: Codable, Equatable {
    /// 用字符串而不是三个布尔，对模型更好读
    public enum Status: String, Codable {
        case active
        case suspended
        case sleeping
    }

    public let id: String
    public let title: String
    public let status: Status
    public let createdAt: String
    /// 挂起时长（秒）；仅挂起态有值
    public let suspendedSeconds: Double?
    /// 本次会话已进行时长（秒）；仅当前在做有值
    public let activeSeconds: Double?
    public let subtasks: [SubtaskDTO]

    public init(id: String,
                title: String,
                status: Status,
                createdAt: String,
                suspendedSeconds: Double?,
                activeSeconds: Double?,
                subtasks: [SubtaskDTO]) {
        self.id = id
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.suspendedSeconds = suspendedSeconds
        self.activeSeconds = activeSeconds
        self.subtasks = subtasks
    }
}

/// 已完成任务，面向外部调用者的表示
public struct CompletedTaskDTO: Codable, Equatable {
    public let id: String
    public let title: String
    public let createdAt: String
    public let finishedAt: String
    /// 是否由「跨周自动结束」产生
    public let autoEnded: Bool
    public let subtasks: [SubtaskDTO]

    public init(id: String,
                title: String,
                createdAt: String,
                finishedAt: String,
                autoEnded: Bool,
                subtasks: [SubtaskDTO]) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.autoEnded = autoEnded
        self.subtasks = subtasks
    }
}
