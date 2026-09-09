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

    init(id: UUID = UUID(),
         title: String,
         createdAt: Date = Date(),
         isActive: Bool = false,
         activeSince: Date? = nil,
         suspendedSince: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.isActive = isActive
        self.activeSince = activeSince
        self.suspendedSince = suspendedSince
    }
}
