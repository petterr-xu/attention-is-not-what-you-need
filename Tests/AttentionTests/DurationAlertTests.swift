import Foundation
import Testing
@testable import Attention

/// 测试用的假通知发送器：不真的弹通知，只记录「发了什么」。
/// 通知本身不进单测（swift-testing 不渲染、也不该真弹），所以副作用必须可注入。
final class SpyNotificationPresenter: NotificationPresenting {
    var authorizationStatus: DurationAlertAuthorization = .authorized
    private(set) var posted: [(title: String, body: String)] = []
    private(set) var requestCount = 0

    func refreshAuthorization(completion: @escaping () -> Void) { completion() }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        requestCount += 1
        completion(authorizationStatus != .denied)
    }

    func post(title: String, body: String) { posted.append((title, body)) }

    func openSystemNotificationSettings() {}

    func installDelegate() {}
}

@Suite("任务时长提醒")
final class DurationAlertTests {
    private let storageURL: URL
    private let state: AppState
    private let spy: SpyNotificationPresenter

    init() {
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("attention-alert-tests-\(UUID().uuidString).json")
        spy = SpyNotificationPresenter()
        state = AppState(storageURL: storageURL,
                         autoEndEnabled: true,
                         startTimers: false,
                         durationAlertEnabled: true,
                         durationAlertThresholdMinutes: 30,
                         notifier: spy)
    }

    deinit {
        try? FileManager.default.removeItem(at: storageURL)
    }

    /// 按固定基准时刻造任务，保证时长断言是确定的
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ minutesAgo: Double) -> Date {
        base.addingTimeInterval(-minutesAgo * 60)
    }

    @discardableResult
    private func seed(_ title: String,
                      minutesAgo: Double,
                      isActive: Bool = false,
                      isSleeping: Bool = false) -> UUID {
        let start = at(minutesAgo)
        let task = TodoTask(title: title,
                            createdAt: start,
                            isActive: isActive,
                            activeSince: isActive ? start : nil,
                            suspendedSince: start,
                            isSleeping: isSleeping)
        state.todos.append(task)
        return task.id
    }

    private func evaluate(now: Date? = nil, firstObservation: Bool = false) {
        state.evaluateDurationAlerts(now: now ?? base, firstObservation: firstObservation)
    }

    // MARK: - 该不该提醒

    @Test("睡眠任务不提醒")
    func sleepingTasksAreSkipped() {
        // sleepTask 不改 suspendedSince，睡眠期时长照样在涨——不显式排除就会被误提醒
        seed("睡着了的任务", minutesAgo: 600, isSleeping: true)

        evaluate()

        #expect(spy.posted.isEmpty)
    }

    @Test("没到阈值不提醒")
    func belowThresholdDoesNotAlert() {
        seed("刚挂起一会儿", minutesAgo: 10)

        evaluate()

        #expect(spy.posted.isEmpty)
    }

    @Test("达到阈值按任务单独提醒一次")
    func crossedThresholdAlerts() {
        seed("晾了很久的任务", minutesAgo: 40)

        evaluate()

        #expect(spy.posted.count == 1)
        #expect(spy.posted.first?.title == "做不到的事是不是就不做了？")
        #expect(spy.posted.first?.body == "晾了很久的任务 已经挂起了 40m")
    }

    @Test("执行中的任务提醒时用的是「执行」")
    func activeTaskSaysExecuting() {
        seed("正在做的任务", minutesAgo: 40, isActive: true)

        evaluate()

        #expect(spy.posted.count == 1)
        #expect(spy.posted.first?.body == "正在做的任务 已经执行了 40m")
    }

    @Test("关闭开关时不提醒")
    func disabledDoesNotAlert() {
        seed("晾了很久的任务", minutesAgo: 40)
        state.durationAlertEnabled = false

        evaluate()

        #expect(spy.posted.isEmpty)
    }

    @Test("未授权时不提醒")
    func unauthorizedDoesNotAlert() {
        spy.authorizationStatus = .denied
        seed("晾了很久的任务", minutesAgo: 40)

        evaluate()

        #expect(spy.posted.isEmpty)
    }

    // MARK: - 同一段状态只提醒一次

    @Test("同一段状态不重复提醒")
    func doesNotRepeatWithinSamePhase() {
        seed("晾了很久的任务", minutesAgo: 40)

        evaluate()
        evaluate(now: base.addingTimeInterval(600))

        #expect(spy.posted.count == 1)
    }

    @Test("状态变化后可以再提醒")
    func alertsAgainAfterPhaseChanges() {
        let id = seed("会被切走的任务", minutesAgo: 40)
        evaluate()
        #expect(spy.posted.count == 1)

        // 模拟「切走再切回」：suspendedSince 被刷新成新的时刻 → 新的幂等键
        state.todos[0].suspendedSince = at(35)
        #expect(state.todos[0].id == id)

        evaluate()

        #expect(spy.posted.count == 2)
    }

    // MARK: - 首次纳入观察走汇总

    @Test("首次纳入观察时多个超时任务压成一条汇总")
    func firstObservationSendsOneSummary() {
        seed("晾了 3 小时的", minutesAgo: 180)
        seed("晾了 1 小时的", minutesAgo: 60)
        seed("还没超时的", minutesAgo: 5)

        evaluate(firstObservation: true)

        #expect(spy.posted.count == 1, "多个超时任务也只发一条")
        #expect(spy.posted.first?.title == "有些事情似乎已经忘了")
        #expect(spy.posted.first?.body == "还有事情等着你去完成，打开 Attention 看看吧")
    }

    @Test("发过汇总之后，运行期不会再把同一批任务逐个重发")
    func summarySuppressesFollowingIndividualAlerts() {
        seed("晾了 3 小时的", minutesAgo: 180)
        seed("晾了 1 小时的", minutesAgo: 60)

        evaluate(firstObservation: true)
        evaluate(firstObservation: false)   // 模拟 60 秒后的定时器

        #expect(spy.posted.count == 1)
    }

    @Test("汇总之后新跨过阈值的任务仍然会单独提醒")
    func newTaskAfterSummaryStillAlerts() {
        seed("晾了 3 小时的", minutesAgo: 180)
        evaluate(firstObservation: true)

        seed("后来才超时的", minutesAgo: 45)
        evaluate(firstObservation: false)

        #expect(spy.posted.count == 2)
        // 标题是固定文案，任务名在正文里
        #expect(spy.posted.last?.body.hasPrefix("后来才超时的 ") == true)
    }

    // MARK: - 阈值

    @Test("把阈值改小后，原本没超时的任务立刻提醒")
    func loweringThresholdTakesEffectImmediately() {
        seed("45 分钟的任务", minutesAgo: 45)

        state.durationAlertThresholdMinutes = 60
        evaluate()
        #expect(spy.posted.isEmpty)

        state.durationAlertThresholdMinutes = 30
        evaluate()

        #expect(spy.posted.count == 1)
    }

    @Test("把阈值改小不会补发已经提醒过的任务")
    func loweringThresholdDoesNotReAlert() {
        seed("40 分钟的任务", minutesAgo: 40)
        evaluate()   // 阈值 30，已提醒
        #expect(spy.posted.count == 1)

        state.durationAlertThresholdMinutes = 1
        evaluate()

        #expect(spy.posted.count == 1, "同一段状态只提醒一次，门槛降了也不补发")
    }

    // MARK: - 开关与授权

    @Test("打开开关会请求授权，被拒则不开启")
    func enablingRequestsAuthorization() {
        spy.authorizationStatus = .denied
        var grantedResult: Bool?

        state.setDurationAlertEnabled(true) { grantedResult = $0 }

        #expect(spy.requestCount == 1)
        #expect(grantedResult == false)
        #expect(state.durationAlertEnabled == false)
    }

    @Test("打开开关且授权通过时，立刻跑一次首轮汇总")
    func enablingRunsFirstObservation() {
        seed("晾了 3 小时的", minutesAgo: 180)

        state.setDurationAlertEnabled(true)

        #expect(state.durationAlertEnabled == true)
        #expect(spy.posted.count == 1)
        #expect(spy.posted.first?.title == "有些事情似乎已经忘了")
    }

    @Test("关闭开关是幂等的")
    func disablingIsIdempotent() {
        state.setDurationAlertEnabled(false)
        state.setDurationAlertEnabled(false)

        #expect(state.durationAlertEnabled == false)
        #expect(spy.requestCount == 0, "关闭不该去请求授权")
    }
}

// MARK: - 纯逻辑

@Suite("时长提醒的文案与格式化")
struct DurationAlertFormattingTests {
    @Test("正文里的时长用 h / m 单位，与列表里显示的格式一致")
    func bodyUsesShortDurationFormat() {
        let candidate = DurationAlertScheduler.Candidate(taskId: UUID(),
                                                         title: "写方案",
                                                         phase: .active,
                                                         since: Date(),
                                                         duration: 135 * 60)

        #expect(DurationAlertScheduler.individualMessage(candidate).body == "写方案 已经执行了 2h 15m")
    }

    @Test("截断按字符算，中英文与 emoji 都不会被切坏")
    func truncation() {
        #expect("短".truncated(to: 20) == "短")
        // 中文按 Character 计，不是按字节（按 utf8 会算成 30）
        #expect("一二三四五六七八九十".truncated(to: 5) == "一二三四五…")
        #expect("abcdefghij".truncated(to: 4) == "abcd…")
        // emoji 是单个 Character，但占 4 字节 / 2 个 UTF-16 单元——按字节或 UTF-16 截会把它切成废码
        #expect("🎉abc".truncated(to: 1) == "🎉…")
        #expect("🎉abc".count == 4)
        #expect("".truncated(to: 5) == "")
    }

    @Test("超长任务名在正文里被截断")
    func longTitleIsTruncatedInMessage() {
        let long = String(repeating: "很长的任务名", count: 6)   // 30 个字符
        let candidate = DurationAlertScheduler.Candidate(taskId: UUID(),
                                                         title: long,
                                                         phase: .suspended,
                                                         since: Date(),
                                                         duration: 3600)
        let message = DurationAlertScheduler.individualMessage(candidate)

        // 标题现在是固定文案，截断落在正文的任务名上
        #expect(message.title == "做不到的事是不是就不做了？")
        let expectedName = String(long.prefix(DurationAlertScheduler.taskTitleCharacterLimit)) + "…"
        #expect(message.body.hasPrefix(expectedName))
        #expect(message.body.hasSuffix(" 已经挂起了 1h 0m"))
    }

    @Test("候选派生会跳过睡眠任务，并区分执行/挂起")
    func candidatesSkipSleeping() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tasks = [
            TodoTask(title: "执行中", createdAt: now, isActive: true,
                     activeSince: now.addingTimeInterval(-600), suspendedSince: now),
            TodoTask(title: "挂起", createdAt: now, suspendedSince: now.addingTimeInterval(-600)),
            TodoTask(title: "睡眠", createdAt: now, suspendedSince: now.addingTimeInterval(-600),
                     isSleeping: true)
        ]

        let candidates = DurationAlertScheduler.candidates(tasks, now: now)

        #expect(candidates.count == 2)
        #expect(candidates.first { $0.title == "执行中" }?.phase == .active)
        #expect(candidates.first { $0.title == "挂起" }?.phase == .suspended)
        #expect(candidates.contains { $0.title == "睡眠" } == false)
    }
}
