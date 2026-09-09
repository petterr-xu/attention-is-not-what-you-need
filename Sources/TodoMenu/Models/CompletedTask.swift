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

    init(id: UUID = UUID(),
         title: String,
         createdAt: Date,
         finishedAt: Date = Date(),
         autoEnded: Bool = false) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.autoEnded = autoEnded
    }
}
