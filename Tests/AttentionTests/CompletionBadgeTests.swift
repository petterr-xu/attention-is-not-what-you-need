import Foundation
import Testing
import AttentionControl
@testable import Attention

/// 已完成入口提示（抖动 + 红点）的行为测试。
///
/// 动画本身不进单测（swift-testing 不渲染视图），所以这里只测两样东西：
/// 触发信号（`finishPulse`）与红点的派生状态（`hasUnseenAutoEnd`），
/// 外加抖动几何那个纯函数的端点。
@Suite("已完成入口提示")
final class CompletionBadgeTests {
    private var storageURL: URL!
    private var state: AppState!

    /// 上一自然周（或更早）的时间，保证会被判定为「跨周过期」
    private var staleDate: Date { Date().addingTimeInterval(-14 * 24 * 3600) }

    private func makeState(autoEndEnabled: Bool = true,
                           aiControlMode: AIControlMode = .off,
                           at url: URL? = nil) -> AppState {
        AppState(storageURL: url ?? storageURL,
                 autoEndEnabled: autoEndEnabled,
                 aiControlMode: aiControlMode,
                 startTimers: false)
    }

    init() {
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("attention-badge-tests-\(UUID().uuidString).json")
        // 这里直接构造：init 里 state 还没赋值，不能调实例方法
        state = AppState(storageURL: storageURL,
                         autoEndEnabled: true,
                         aiControlMode: .off,
                         startTimers: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: storageURL)
    }

    /// 造一个过期任务，让 `autoEndStaleTasks()` 会把它移走
    private func seedStaleTask(_ title: String = "过期任务") -> UUID {
        let task = TodoTask(title: title, createdAt: staleDate, suspendedSince: staleDate)
        state.todos.append(task)
        return task.id
    }

    // MARK: - 红点：自动结束置位

    @Test("跨周自动结束会亮红点")
    func autoEndLightsBadge() {
        _ = seedStaleTask()
        #expect(state.hasUnseenAutoEnd == false)

        state.autoEndStaleTasks()

        #expect(state.completed.count == 1)
        #expect(state.completed.first?.autoEnded == true)
        #expect(state.hasUnseenAutoEnd == true)
    }

    @Test("查看后红点消失")
    func viewingClearsBadge() {
        _ = seedStaleTask()
        state.autoEndStaleTasks()
        #expect(state.hasUnseenAutoEnd == true)

        state.markCompletedViewed()

        #expect(state.hasUnseenAutoEnd == false)
    }

    @Test("关掉跨周自动结束时不置红点")
    func disabledAutoEndDoesNotLightBadge() {
        state = makeState(autoEndEnabled: false)
        _ = seedStaleTask()

        state.autoEndStaleTasks()

        #expect(state.completed.isEmpty)
        #expect(state.hasUnseenAutoEnd == false)
    }

    @Test("查看之后新到的自动结束会重新亮起")
    func newAutoEndAfterViewingLightsAgain() {
        _ = seedStaleTask()
        state.autoEndStaleTasks()
        state.markCompletedViewed()
        #expect(state.hasUnseenAutoEnd == false)

        _ = seedStaleTask("又来一个过期的")
        state.autoEndStaleTasks()

        #expect(state.hasUnseenAutoEnd == true)
    }

    // MARK: - 红点：手动结束不参与

    @Test("手动结束不亮红点")
    func manualFinishDoesNotLightBadge() {
        let id = UUID()
        state.todos.append(TodoTask(id: id, title: "手动结束的"))

        state.finishTask(id: id, source: .user)

        #expect(state.completed.count == 1)
        #expect(state.completed.first?.autoEnded == false)
        #expect(state.hasUnseenAutoEnd == false)
    }

    // MARK: - 抖动脉冲

    @Test("手动结束会递增抖动脉冲")
    func manualFinishPulses() {
        let first = UUID()
        let second = UUID()
        state.todos.append(TodoTask(id: first, title: "一"))
        state.todos.append(TodoTask(id: second, title: "二"))
        #expect(state.finishPulse == 0)

        state.finishTask(id: first, source: .user)
        state.finishTask(id: second, source: .user)

        #expect(state.finishPulse == 2)
    }

    @Test("AI 通过 MCP 结束不抖动")
    func aiFinishDoesNotPulse() {
        state = makeState(aiControlMode: .open)
        let id = UUID()
        state.todos.append(TodoTask(id: id, title: "AI 结束的"))

        let response = ControlDispatcher.dispatch(.finishTask(id: id), state: state)

        #expect(response == .ok)
        #expect(state.completed.count == 1)
        #expect(state.finishPulse == 0)
    }

    @Test("结束不存在的任务既不抖动也不进已完成")
    func finishingUnknownTaskDoesNothing() {
        state.finishTask(id: UUID(), source: .user)

        #expect(state.finishPulse == 0)
        #expect(state.completed.isEmpty)
    }

    // MARK: - 持久化

    @Test("没查看就退出，重开后红点仍在")
    func badgeSurvivesRelaunch() {
        _ = seedStaleTask()
        state.autoEndStaleTasks()
        #expect(state.hasUnseenAutoEnd == true)
        // 关键：这里刻意不调 markCompletedViewed()，模拟用户没看就退出

        let reopened = makeState()

        #expect(reopened.completed.count == 1)
        #expect(reopened.hasUnseenAutoEnd == true)
    }

    @Test("查看过之后退出，重开不再亮")
    func clearedBadgeStaysClearedAfterRelaunch() {
        _ = seedStaleTask()
        state.autoEndStaleTasks()
        state.markCompletedViewed()

        let reopened = makeState()

        #expect(reopened.hasUnseenAutoEnd == false)
    }

    @Test("不含 lastCompletedViewedAt 的旧数据解码为「已读」")
    func legacyDataWithoutWatermarkDecodesAsSeen() throws {
        // 手写一份旧格式：有 autoEnded 的已完成任务，但没有水位线字段。
        // 默认值必须落在「解码那一刻」，否则升级用户会看到一颗不知道指向什么的红点。
        let legacy = """
        {
          "todos": [],
          "completed": [
            {
              "id": "\(UUID().uuidString)",
              "title": "升级前就存在的自动结束任务",
              "createdAt": 0,
              "finishedAt": 0,
              "autoEnded": true,
              "subtasks": []
            }
          ]
        }
        """
        try Data(legacy.utf8).write(to: storageURL)

        let loaded = makeState()

        #expect(loaded.completed.count == 1)
        #expect(loaded.hasUnseenAutoEnd == false, "历史存量不该背着一颗红点")
    }

    @Test("旧数据 + 新的自动结束，红点照常亮")
    func legacyDataStillReactsToNewAutoEnd() throws {
        try Data(#"{"todos":[],"completed":[]}"#.utf8).write(to: storageURL)
        let loaded = makeState()
        #expect(loaded.hasUnseenAutoEnd == false)

        let task = TodoTask(title: "新的过期任务", createdAt: staleDate, suspendedSince: staleDate)
        loaded.todos.append(task)
        loaded.autoEndStaleTasks()

        #expect(loaded.hasUnseenAutoEnd == true)
    }

    // MARK: - 抖动几何

    @Test("抖动在起止两端位移归零，中途达到峰值")
    func shakeOffsetEndpointsAreZero() {
        let amplitude: CGFloat = 6

        // 这两条是「图标不会永久歪着」的保证：模型值落在整数刻度上时投影就是恒等变换。
        // 用容差而不是 == 0：sin(6π) 算出来是 -4.4e-15，浮点误差在 pt 尺度上完全不可见。
        #expect(abs(ShakeEffect.offset(progress: 0, amplitude: amplitude)) < 1e-9)
        #expect(abs(ShakeEffect.offset(progress: 1, amplitude: amplitude)) < 1e-9)

        // 中途确实是抖起来的，不是恒等于 0
        #expect(abs(ShakeEffect.offset(progress: 0.25, amplitude: amplitude)) == amplitude)
    }
}
