import Foundation

/// 时长提醒的纯逻辑：谁该被提醒、文案是什么。
///
/// 刻意不碰 `AppState` 与通知发送，这样它能脱离 socket / runloop 直接单测。
enum DurationAlertScheduler {
    enum Phase: String {
        case active
        case suspended
    }

    /// 一个「该不该提醒」的候选
    struct Candidate: Equatable {
        let taskId: UUID
        let title: String
        let phase: Phase
        /// 该状态段的起始时刻（`activeSince` 或 `suspendedSince`）
        let since: Date
        let duration: TimeInterval

        /// 幂等键：同一任务 + 同一阶段 + 同一段起始时刻 = 一次提醒机会。
        ///
        /// 它在各种状态变化下会**自然**改变，不需要额外的失效逻辑：
        /// 切走 → `suspendedSince = now`；切回 → 新 `activeSince`；唤醒 → 新 `suspendedSince`；
        /// 重启 → `activeSince` 清零（active 键消失，本来也不该提醒）、`suspendedSince` 保留。
        var key: String {
            "\(taskId.uuidString)|\(phase.rawValue)|\(since.timeIntervalSince1970)"
        }
    }

    /// 通知里任务名最多显示多少个字符
    static let taskTitleCharacterLimit = 20

    /// 派生当前所有候选。**睡眠任务被排除**。
    static func candidates(_ tasks: [TodoTask], now: Date) -> [Candidate] {
        tasks.compactMap { task in
            // 睡眠任务必须显式排除：`sleepTask` 不改 `suspendedSince`，睡眠期时长照样在涨，
            // 不排除的话睡眠任务会被误提醒。
            guard !task.isSleeping else { return nil }

            // 注意不要复用 `AppState.activeDuration()` —— 它内部是
            // `todos.first(where: { $0.isActive })`，只返回当前那一个任务的时长。
            if task.isActive, let since = task.activeSince {
                return Candidate(taskId: task.id,
                                 title: task.title,
                                 phase: .active,
                                 since: since,
                                 duration: now.timeIntervalSince(since))
            }
            return Candidate(taskId: task.id,
                             title: task.title,
                             phase: .suspended,
                             since: task.suspendedSince,
                             duration: now.timeIntervalSince(task.suspendedSince))
        }
    }

    /// 运行期单条提醒：(标题, 正文)。
    /// 标题是一句固定的提问，任务名放正文里——形如「⟨任务名⟩ 已经挂起了 2h 15m」。
    static func individualMessage(_ candidate: Candidate) -> (title: String, body: String) {
        let name = candidate.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .truncated(to: taskTitleCharacterLimit)
        let verb = candidate.phase == .active ? "执行" : "挂起"
        return ("做不到的事是不是就不做了？",
                "\(name) 已经\(verb)了 \(TimeFormatter.string(from: candidate.duration))")
    }

    /// 首次纳入观察时的汇总提醒：(标题, 正文)。不报具体时长，只把人叫回来。
    static func summaryMessage() -> (title: String, body: String) {
        ("有些事情似乎已经忘了",
         "还有事情等着你去完成，打开 Attention 看看吧")
    }
}
