import Foundation

/// 待办任务
struct TodoTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    /// 创建时间（用于「跨自然周自动结束」判定）
    var createdAt: Date
    /// 是否为当前正在做的任务
    var isActive: Bool
    /// 本次会话开始时间（切走即置 nil，单次会话计时）
    var activeSince: Date?
    /// 挂起/创建开始时间（挂起时长基准）
    var suspendedSince: Date
    /// 子任务列表（固定按添加顺序）
    var subtasks: [Subtask]

    init(id: UUID = UUID(),
         title: String,
         createdAt: Date = Date(),
         isActive: Bool = false,
         activeSince: Date? = nil,
         suspendedSince: Date = Date(),
         subtasks: [Subtask] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.isActive = isActive
        self.activeSince = activeSince
        self.suspendedSince = suspendedSince
        self.subtasks = subtasks
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, isActive, activeSince, suspendedSince, subtasks
    }

    /// 自定义解码：subtasks 缺省为 []，兼容无子任务的旧数据
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        activeSince = try c.decodeIfPresent(Date.self, forKey: .activeSince)
        suspendedSince = try c.decode(Date.self, forKey: .suspendedSince)
        subtasks = try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isActive, forKey: .isActive)
        try c.encodeIfPresent(activeSince, forKey: .activeSince)
        try c.encode(suspendedSince, forKey: .suspendedSince)
        try c.encode(subtasks, forKey: .subtasks)
    }
}
