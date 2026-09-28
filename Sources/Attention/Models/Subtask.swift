import Foundation

/// 子任务：跟随父任务生命周期，无计时，仅完成标记。
/// 排序固定为添加顺序（数组顺序），不提供排序能力。
struct Subtask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    /// 是否已完成（勾选标记，勾选后仅变灰，不影响排序与生命周期）
    var isDone: Bool

    init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}
