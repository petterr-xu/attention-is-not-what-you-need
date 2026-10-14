import Foundation
import AttentionControl

/// 唯一一处「懂 `AppState`」的控制层代码：把外部命令翻译成 AppState 的调用，
/// 再把结果翻译成对外的 DTO。
///
/// 写成同步纯函数（不碰 socket、不碰 runloop）是刻意的——这样它能被直接单测，
/// 而真 socket 那一层另有测试覆盖。
enum ControlDispatcher {
    private static let iso8601 = ISO8601DateFormatter()

    static func dispatch(_ command: ControlCommand,
                         state: AppState,
                         now: Date = Date()) -> ControlResponse {
        // 三档门禁：关闭 = 什么都不放行；安全 = 只放行只读命令；开放 = 全放行
        if state.aiControlMode == .off {
            return .failure(.aiDisabled())
        }
        if state.aiControlMode == .safe && command.isMutation {
            return .failure(.readOnly(command.name))
        }
        return execute(command, state: state, now: now)
    }

    private static func execute(_ command: ControlCommand,
                                state: AppState,
                                now: Date) -> ControlResponse {
        // 穷尽 switch：将来给 ControlCommand 加 case 时，这里漏掉会直接编译报错
        switch command {
        case .listTasks:
            return .tasks(state.sortedTodos.map { taskDTO($0, state: state, now: now) })

        case .getActiveTask:
            guard let id = state.activeTaskId,
                  let task = state.todos.first(where: { $0.id == id }) else {
                return .activeTask(nil)
            }
            return .activeTask(taskDTO(task, state: state, now: now))

        case .listCompleted:
            return .completed(state.completed.map(completedDTO))

        case .addTask(let title):
            let before = state.todos.count
            state.addTask(title: title)
            // AppState.addTask 对空标题是静默 no-op；靠数量变化判定，否则会给模型一个假成功
            guard state.todos.count > before else {
                return .failure(ControlError(.invalidArgument, "任务标题不能为空"))
            }
            return .ok

        case .renameTask(let id, let title):
            guard state.todos.contains(where: { $0.id == id }) else { return notFound("待办", id) }
            guard !title.isBlank else {
                return .failure(ControlError(.invalidArgument, "任务标题不能为空"))
            }
            state.renameTask(id: id, newTitle: title)
            return .ok

        case .setActiveTask(let id):
            guard state.todos.contains(where: { $0.id == id }) else { return notFound("待办", id) }
            // activateTask 是三合一 toggle：对「已经是当前」的任务再调一次会把它取消掉。
            // 「set」必须幂等，所以这里自己守卫，不能直接转发。
            guard state.activeTaskId != id else { return .ok }
            state.activateTask(id: id)
            return .ok

        case .clearActiveTask:
            // 同样是对 toggle 的适配：「取消当前」== 对当前任务再点一次
            guard let id = state.activeTaskId else { return .ok }
            state.activateTask(id: id)
            return .ok

        case .sleepTask(let id):
            guard state.todos.contains(where: { $0.id == id }) else { return notFound("待办", id) }
            state.sleepTask(id: id)
            return .ok

        case .wakeTask(let id):
            guard state.todos.contains(where: { $0.id == id }) else { return notFound("待办", id) }
            state.wakeTask(id: id)
            return .ok

        case .finishTask(let id):
            guard state.todos.contains(where: { $0.id == id }) else { return notFound("待办", id) }
            // 来源是 AI：不驱动入口图标抖动（用户没做任何操作时图标不该自己动）
            state.finishTask(id: id, source: .ai)
            return .ok

        case .restoreTask(let id):
            guard state.completed.contains(where: { $0.id == id }) else { return notFound("已完成", id) }
            state.restoreTask(id: id)
            return .ok

        case .addSubtask(let parentId, let title):
            guard state.todos.contains(where: { $0.id == parentId }) else { return notFound("待办", parentId) }
            let before = subtaskCount(state, parentId)
            state.addSubtask(toParent: parentId, title: title)
            guard subtaskCount(state, parentId) > before else {
                return .failure(ControlError(.invalidArgument, "子任务标题不能为空"))
            }
            return .ok

        case .renameSubtask(let parentId, let subtaskId, let title):
            guard state.todos.contains(where: { $0.id == parentId }) else { return notFound("待办", parentId) }
            guard hasSubtask(state, parentId, subtaskId) else { return notFound("子任务", subtaskId) }
            guard !title.isBlank else {
                return .failure(ControlError(.invalidArgument, "子任务标题不能为空"))
            }
            state.renameSubtask(parentId: parentId, subtaskId: subtaskId, newTitle: title)
            return .ok

        case .toggleSubtask(let parentId, let subtaskId):
            guard state.todos.contains(where: { $0.id == parentId }) else { return notFound("待办", parentId) }
            guard hasSubtask(state, parentId, subtaskId) else { return notFound("子任务", subtaskId) }
            state.toggleSubtask(parentId: parentId, subtaskId: subtaskId)
            return .ok
        }
    }

    // MARK: - 辅助

    private static func subtaskCount(_ state: AppState, _ parentId: UUID) -> Int {
        state.todos.first(where: { $0.id == parentId })?.subtasks.count ?? 0
    }

    private static func hasSubtask(_ state: AppState, _ parentId: UUID, _ subtaskId: UUID) -> Bool {
        state.todos.first(where: { $0.id == parentId })?
            .subtasks.contains(where: { $0.id == subtaskId }) ?? false
    }

    private static func notFound(_ what: String, _ id: UUID) -> ControlResponse {
        .failure(ControlError(.notFound, "找不到\(what)任务：\(id.uuidString)"))
    }

    // MARK: - DTO

    private static func taskDTO(_ task: TodoTask, state: AppState, now: Date) -> TaskDTO {
        let status: TaskDTO.Status
        if task.isActive {
            status = .active
        } else if task.isSleeping {
            status = .sleeping
        } else {
            status = .suspended
        }

        return TaskDTO(
            id: task.id.uuidString,
            title: task.title,
            status: status,
            createdAt: iso8601.string(from: task.createdAt),
            // 睡眠任务不计时，所以两个时长都不给
            suspendedSeconds: status == .suspended ? state.suspendedDuration(task, now: now) : nil,
            activeSeconds: status == .active ? state.activeDuration(now: now) : nil,
            subtasks: task.subtasks.map(subtaskDTO))
    }

    private static func completedDTO(_ task: CompletedTask) -> CompletedTaskDTO {
        CompletedTaskDTO(id: task.id.uuidString,
                         title: task.title,
                         createdAt: iso8601.string(from: task.createdAt),
                         finishedAt: iso8601.string(from: task.finishedAt),
                         autoEnded: task.autoEnded,
                         subtasks: task.subtasks.map(subtaskDTO))
    }

    private static func subtaskDTO(_ subtask: Subtask) -> SubtaskDTO {
        SubtaskDTO(id: subtask.id.uuidString, title: subtask.title, isDone: subtask.isDone)
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
