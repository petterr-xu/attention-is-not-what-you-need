import Foundation
import Testing
import AttentionControl
@testable import Attention

/// 控制层（MCP 接口的落地层）的行为测试。
///
/// `ControlDispatcher.dispatch` 是同步纯函数，所以这一批测试不需要 socket、不需要 runloop，
/// 直接对 AppState 的可观察结果断言即可。
@Suite("控制层分发")
final class ControlDispatcherTests {
    private let state: AppState
    private let storageURL: URL

    init() {
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("attention-control-tests-\(UUID().uuidString).json")
        state = AppState(storageURL: storageURL,
                         autoEndEnabled: true,
                         aiControlMode: .open,
                         startTimers: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: storageURL)
    }

    private func dispatch(_ command: ControlCommand) -> ControlResponse {
        ControlDispatcher.dispatch(command, state: state)
    }

    private func addTask(_ title: String) -> UUID {
        _ = dispatch(.addTask(title: title))
        return state.todos.last!.id
    }

    // MARK: - 三档门禁

    @Test("关闭模式下任何命令都被拒绝")
    func offModeRejectsEverything() {
        state.aiControlMode = .off

        for command in [ControlCommand.listTasks, .addTask(title: "x")] {
            guard case .failure(let error) = dispatch(command) else {
                Issue.record("\(command.name) 本应被拒绝")
                return
            }
            #expect(error.kind == .aiControlDisabled)
        }
    }

    @Test("安全模式放行读、拒绝写")
    func safeModeAllowsReadsOnly() {
        state.aiControlMode = .safe

        guard case .tasks = dispatch(.listTasks) else {
            Issue.record("安全模式下 list_tasks 应当放行")
            return
        }

        guard case .failure(let error) = dispatch(.addTask(title: "写操作")) else {
            Issue.record("安全模式下 add_task 本应被拒绝")
            return
        }
        #expect(error.kind == .readOnlyMode)
        #expect(state.todos.isEmpty, "被拒绝的写操作不应产生任何副作用")
    }

    @Test("开放模式读写都放行")
    func openModeAllowsWrites() {
        let id = addTask("写操作")
        #expect(state.todos.count == 1)
        #expect(state.todos.first?.id == id)
    }

    // MARK: - 读

    @Test("list_tasks 按列表顺序返回，并带上状态")
    func listTasks() {
        let suspended = addTask("挂起")
        let sleeping = addTask("睡眠")
        _ = dispatch(.sleepTask(id: sleeping))

        guard case .tasks(let tasks) = dispatch(.listTasks) else {
            Issue.record("list_tasks 应返回 tasks")
            return
        }
        #expect(tasks.count == 2)
        // 睡眠任务沉底
        #expect(tasks.last?.id == sleeping.uuidString)
        #expect(tasks.last?.status == .sleeping)
        #expect(tasks.first?.id == suspended.uuidString)
        #expect(tasks.first?.status == .suspended)
        // 睡眠任务不计时，两个时长都不给
        #expect(tasks.last?.suspendedSeconds == nil)
    }

    @Test("没有当前任务时 get_active_task 返回 null")
    func getActiveTaskWhenNone() {
        addTask("普通任务")
        #expect(dispatch(.getActiveTask) == .activeTask(nil))
    }

    // MARK: - 当前任务（toggle 语义的适配）

    @Test("set_active_task 幂等：对当前任务再设一次不会取消它")
    func setActiveTaskIsIdempotent() {
        let id = addTask("任务")

        _ = dispatch(.setActiveTask(id: id))
        #expect(state.activeTaskId == id)

        // 关键：AppState.activateTask 是 toggle，直接转发会把任务取消掉
        _ = dispatch(.setActiveTask(id: id))
        #expect(state.activeTaskId == id, "重复设置不应把当前任务取消")
    }

    @Test("set_active_task 会把原当前任务转为挂起")
    func setActiveTaskSuspendsPrevious() {
        let first = addTask("第一个")
        let second = addTask("第二个")

        _ = dispatch(.setActiveTask(id: first))
        _ = dispatch(.setActiveTask(id: second))

        #expect(state.activeTaskId == second)
        #expect(state.todos.first(where: { $0.id == first })?.isActive == false)
    }

    @Test("clear_active_task 取消当前任务；没有当前任务时是空操作")
    func clearActiveTask() {
        let id = addTask("任务")

        #expect(dispatch(.clearActiveTask) == .ok)
        #expect(state.activeTaskId == nil)

        _ = dispatch(.setActiveTask(id: id))
        #expect(dispatch(.clearActiveTask) == .ok)
        #expect(state.activeTaskId == nil)
    }

    // MARK: - 坏输入必须报错，不能静默成功

    @Test("坏 id 返回 notFound，而不是假成功")
    func badIdReportsNotFound() {
        let ghost = UUID()

        for command in [ControlCommand.finishTask(id: ghost),
                        .sleepTask(id: ghost),
                        .wakeTask(id: ghost),
                        .renameTask(id: ghost, title: "x"),
                        .setActiveTask(id: ghost)] {
            guard case .failure(let error) = dispatch(command) else {
                Issue.record("\(command.name) 对不存在的 id 本应报错")
                return
            }
            #expect(error.kind == .notFound)
        }
    }

    @Test("空标题返回 invalidArgument，而不是假成功")
    func blankTitleReportsInvalid() {
        guard case .failure(let error) = dispatch(.addTask(title: "   ")) else {
            Issue.record("空标题本应报错")
            return
        }
        #expect(error.kind == .invalidArgument)
        #expect(state.todos.isEmpty)
    }

    @Test("restore_task 只认已完成列表里的 id")
    func restoreOnlyAcceptsCompletedIDs() {
        let id = addTask("待办里的任务")
        guard case .failure(let error) = dispatch(.restoreTask(id: id)) else {
            Issue.record("不在已完成列表里的 id 本应报错")
            return
        }
        #expect(error.kind == .notFound)
    }

    // MARK: - 全流程

    @Test("结束 → 放回 的往返")
    func finishAndRestore() {
        let id = addTask("任务")

        #expect(dispatch(.finishTask(id: id)) == .ok)
        #expect(state.todos.isEmpty)
        #expect(state.completed.count == 1)

        #expect(dispatch(.restoreTask(id: id)) == .ok)
        #expect(state.todos.count == 1)
        #expect(state.completed.isEmpty)
    }

    @Test("子任务：添加、重命名、勾选")
    func subtasks() {
        let id = addTask("父任务")

        #expect(dispatch(.addSubtask(parentId: id, title: "子任务")) == .ok)
        let subtaskId = try! #require(state.todos.first?.subtasks.first?.id)

        #expect(dispatch(.renameSubtask(parentId: id, subtaskId: subtaskId, title: "改名了")) == .ok)
        #expect(state.todos.first?.subtasks.first?.title == "改名了")

        #expect(dispatch(.toggleSubtask(parentId: id, subtaskId: subtaskId)) == .ok)
        #expect(state.todos.first?.subtasks.first?.isDone == true)

        guard case .failure(let error) = dispatch(.toggleSubtask(parentId: id, subtaskId: UUID())) else {
            Issue.record("坏 subtaskId 本应报错")
            return
        }
        #expect(error.kind == .notFound)
    }

    @Test("睡眠与唤醒")
    func sleepAndWake() {
        let id = addTask("任务")

        #expect(dispatch(.sleepTask(id: id)) == .ok)
        #expect(state.todos.first?.isSleeping == true)

        #expect(dispatch(.wakeTask(id: id)) == .ok)
        #expect(state.todos.first?.isSleeping == false)
    }
}
