import Foundation
import Testing
@testable import Attention

/// 睡眠（sleep / wake up）功能的行为测试。
/// 只断言 AppState 的外部可观察行为（排序结果、状态字段、自动结束效果），不触碰实现细节。
///
/// 用 swift-testing（`Testing` 模块）而非 XCTest：本机只有 Command Line Tools，
/// CLT 不带 XCTest，但自带 swift-testing，与「无需完整 Xcode」的构建前提一致。
@Suite("睡眠")
final class SleepTests {
    private let state: AppState
    private let storageURL: URL

    /// 固定基准时间，避免依赖 Date() 的亚毫秒精度导致排序结果不确定
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    init() {
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("attention-sleep-tests-\(UUID().uuidString).json")
        state = AppState(storageURL: storageURL, autoEndEnabled: true, startTimers: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: storageURL)
    }

    // MARK: - 工具

    private func task(_ title: String,
                      createdAt: Date? = nil,
                      suspendedSince: Date? = nil,
                      isSleeping: Bool = false) -> TodoTask {
        TodoTask(title: title,
                 createdAt: createdAt ?? base,
                 suspendedSince: suspendedSince ?? base,
                 isSleeping: isSleeping)
    }

    private func titles() -> [String] {
        state.sortedTodos.map(\.title)
    }

    /// 测试夹具：任务由测试自己构造，找不到即测试写错了
    private func stored(_ title: String) -> TodoTask {
        guard let task = state.todos.first(where: { $0.title == title }) else {
            Issue.record("待办列表中找不到任务 \(title)")
            fatalError("任务 \(title) 不存在")
        }
        return task
    }

    // MARK: - 排序

    @Test("睡眠任务沉到列表最下方")
    func sleepingTaskSortsToBottom() {
        // A 挂起最久（正常规则下应排最前），睡眠后必须沉底
        state.todos = [
            task("A", suspendedSince: base),
            task("B", suspendedSince: base.addingTimeInterval(60)),
            task("C", suspendedSince: base.addingTimeInterval(120)),
        ]

        state.sleepTask(id: stored("A").id)

        #expect(titles() == ["B", "C", "A"])
        #expect(stored("A").isSleeping)
    }

    @Test("其他任务的顺序变化影响不到睡眠任务的位置")
    func sleepingTaskPositionUnaffectedByOtherChanges() {
        state.todos = [
            task("A", suspendedSince: base),
            task("B", suspendedSince: base.addingTimeInterval(60)),
            task("C", suspendedSince: base.addingTimeInterval(120)),
        ]
        state.sleepTask(id: stored("A").id)

        // 其他任务来回切换当前/挂起/结束，睡眠任务都应垫底
        state.activateTask(id: stored("C").id)
        #expect(titles().last == "A")
        state.activateTask(id: stored("C").id)
        #expect(titles().last == "A")
        state.activateTask(id: stored("B").id)
        #expect(titles().last == "A")
        state.finishTask(id: stored("B").id, source: .ai)   // 本用例不关心抖动来源
        #expect(titles().last == "A")
    }

    // MARK: - 状态互斥

    @Test("睡眠当前任务会一并取消其「当前在做」状态")
    func sleepingCurrentTaskClearsActive() {
        state.todos = [task("A"), task("B", suspendedSince: base.addingTimeInterval(60))]
        state.activateTask(id: stored("A").id)
        #expect(state.activeTaskId == stored("A").id)

        state.sleepTask(id: stored("A").id)

        #expect(!stored("A").isActive)
        #expect(stored("A").activeSince == nil)
        #expect(state.activeTaskId == nil)
    }

    // MARK: - 唤醒

    @Test("唤醒重置 createdAt 与 suspendedSince")
    func wakeResetsCreatedAtAndSuspendedSince() {
        let old = base.addingTimeInterval(-30 * 24 * 3600)
        state.todos = [task("A", createdAt: old, suspendedSince: old, isSleeping: true)]

        let before = Date()
        state.wakeTask(id: stored("A").id)
        let after = Date()

        let woken = stored("A")
        #expect(!woken.isSleeping)
        #expect(before...after ~= woken.createdAt, "createdAt 应被重置为唤醒时刻")
        #expect(before...after ~= woken.suspendedSince, "suspendedSince 应被重置为唤醒时刻")
    }

    @Test("唤醒后落到活跃组最下方")
    func wokenTaskLandsAfterOtherSuspendedTasks() {
        state.todos = [
            task("A", suspendedSince: base, isSleeping: true),
            task("B", suspendedSince: base.addingTimeInterval(60)),
            task("C", suspendedSince: base.addingTimeInterval(120)),
        ]

        state.wakeTask(id: stored("A").id)

        // A 刚被挂起（suspendedSince 最新），落在 B、C 之后
        #expect(titles() == ["B", "C", "A"])
    }

    @Test("激活睡眠任务等同于唤醒 + 设为当前")
    func activatingSleepingTaskWakesIt() {
        state.todos = [task("A", isSleeping: true)]

        state.activateTask(id: stored("A").id)

        #expect(!stored("A").isSleeping)
        #expect(stored("A").isActive)
    }

    // MARK: - 跨周自动结束

    @Test("睡眠任务不被跨周自动结束")
    func sleepingTaskNotAutoEnded() {
        let lastWeek = Date().addingTimeInterval(-14 * 24 * 3600)
        state.todos = [
            task("sleeping", createdAt: lastWeek, suspendedSince: lastWeek, isSleeping: true),
            task("normal", createdAt: lastWeek, suspendedSince: lastWeek),
        ]

        state.autoEndStaleTasks()

        #expect(state.todos.map(\.title) == ["sleeping"])
        #expect(state.completed.map(\.title) == ["normal"])
    }

    @Test("唤醒后不会被跨周自动结束")
    func wokenTaskSurvivesAutoEnd() {
        let lastWeek = Date().addingTimeInterval(-14 * 24 * 3600)
        state.todos = [task("A", createdAt: lastWeek, suspendedSince: lastWeek, isSleeping: true)]

        state.wakeTask(id: stored("A").id)
        state.autoEndStaleTasks()

        #expect(state.todos.map(\.title) == ["A"], "唤醒后应视作刚创建，不被跨周自动结束")
        #expect(state.completed.isEmpty)
    }

    // MARK: - 持久化

    @Test("睡眠状态跨重启保留")
    func sleepingStatePersistsAcrossReload() {
        state.todos = [task("A", isSleeping: true)]

        let reloaded = AppState(storageURL: storageURL, autoEndEnabled: true, startTimers: false)

        #expect(reloaded.todos.first { $0.title == "A" }?.isSleeping == true)
    }

    @Test("不含 isSleeping 的旧数据解码为非睡眠")
    func legacyTaskWithoutIsSleepingDecodesAsAwake() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "legacy",
          "createdAt": 0,
          "isActive": false,
          "activeSince": null,
          "suspendedSince": 0,
          "subtasks": []
        }
        """

        let decoded = try JSONDecoder().decode(TodoTask.self, from: Data(json.utf8))

        #expect(!decoded.isSleeping)
    }

    @Test("isSleeping 编解码往返一致")
    func isSleepingRoundTrips() throws {
        let original = task("A", isSleeping: true)

        let decoded = try JSONDecoder().decode(TodoTask.self,
                                               from: try JSONEncoder().encode(original))

        #expect(decoded.isSleeping)
        #expect(decoded == original)
    }
}
