import Foundation

/// 已完成任务（结束的任务进入此列表，可放回待办）
struct CompletedTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    /// 结束时间（用于「当天结束」判定）
    var finishedAt: Date
    /// 是否由「跨周自动结束」产生（用于 UI 标注）
    var autoEnded: Bool
    /// 子任务列表（随父任务一起完成，仅只读查看）
    var subtasks: [Subtask]

    init(id: UUID = UUID(),
         title: String,
         createdAt: Date,
         finishedAt: Date = Date(),
         autoEnded: Bool = false,
         subtasks: [Subtask] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.autoEnded = autoEnded
        self.subtasks = subtasks
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, finishedAt, autoEnded, subtasks
    }

    /// 自定义解码：subtasks 缺省为 []，兼容无子任务的旧数据
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        finishedAt = try c.decode(Date.self, forKey: .finishedAt)
        autoEnded = try c.decode(Bool.self, forKey: .autoEnded)
        subtasks = try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(finishedAt, forKey: .finishedAt)
        try c.encode(autoEnded, forKey: .autoEnded)
        try c.encode(subtasks, forKey: .subtasks)
    }
}
