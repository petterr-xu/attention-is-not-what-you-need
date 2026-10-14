import Foundation
import Combine

/// AI 通过 MCP 操作待办的权限档位。
enum AIControlMode: String, CaseIterable {
    /// 任何调用都被拒绝
    case off
    /// 只允许读（list / get）
    case safe
    /// 读写都允许
    case open

    var title: String {
        switch self {
        case .off: return "关闭"
        case .safe: return "安全（只读）"
        case .open: return "开放（读写）"
        }
    }
}

/// 结束任务的来源。只有用户自己点的才驱动入口图标抖动。
enum FinishSource {
    case user
    /// 经 MCP 接口由 AI 触发
    case ai
}

/// 全局应用状态单例：待办/已完成列表、计时、排序、持久化、自动结束。
/// 菜单栏面板与悬浮窗共享同一个实例。
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var todos: [TodoTask] = [] {
        didSet { if !isLoading { save() } }
    }
    @Published var completed: [CompletedTask] = [] {
        didSet { if !isLoading { save() } }
    }
    /// 悬浮窗是否展示（开关）
    @Published var showFloatingPanel: Bool {
        didSet { persistPreference(showFloatingPanel, forKey: "showFloatingPanel") }
    }
    /// 悬浮窗是否折叠成小条
    @Published var isPanelCollapsed = false
    /// 是否自动结束跨自然周的待办任务（默认开启）
    @Published var autoEndEnabled: Bool {
        didSet { persistPreference(autoEndEnabled, forKey: "autoEndEnabled") }
    }
    /// AI 通过 MCP 操作待办的权限档位（默认关闭）
    @Published var aiControlMode: AIControlMode {
        didSet { persistPreference(aiControlMode.rawValue, forKey: Self.aiControlModeKey) }
    }
    /// 「已完成列表」上次被查看的时刻。早于它的自动结束任务不再算「未查看」。
    @Published private(set) var lastCompletedViewedAt: Date {
        didSet { if !isLoading { save() } }
    }
    /// 用户手动结束任务的脉冲：每次 +1，供入口图标做抖动反馈。不持久化。
    ///
    /// 用计数器而不是布尔——布尔 `true → true` 不算变化，`onChange` 不会触发，
    /// 第二次结束就不抖了。
    @Published private(set) var finishPulse = 0
    /// 任务时长提醒开关（默认关闭）
    @Published var durationAlertEnabled: Bool {
        didSet { persistPreference(durationAlertEnabled, forKey: Self.durationAlertEnabledKey) }
    }
    /// 时长提醒阈值（分钟）
    @Published var durationAlertThresholdMinutes: Int {
        didSet { persistPreference(durationAlertThresholdMinutes, forKey: Self.durationAlertThresholdKey) }
    }

    private var tickTimer: Timer?
    private var autoEndTimer: Timer?
    private var durationAlertTimer: Timer?
    private var isLoading = false
    private let storageURL: URL
    /// 是否把偏好写回 UserDefaults。
    ///
    /// 注入构造出来的隔离实例（`startTimers == false`，测试在用）不写——否则用例会把
    /// 开发者**真机上**的设置改掉（比如测试里打开一次时长提醒，真机 app 就被开启了）。
    private let persistsPreferences: Bool
    /// 通知发送。可注入，测试用替身断言「发了什么」。
    let notifier: NotificationPresenting
    /// 已提醒过的「任务 + 状态段」键。
    ///
    /// **只放内存、不持久化**：需求要的就是「启动时发现有超时任务就发一条汇总」，
    /// 所以每次启动重新观察一轮、重发一次汇总是预期行为；持久化反而会让第二次启动不再汇总。
    private var alertedKeys: Set<String> = []
    private static let aiControlModeKey = "aiControlMode"
    private static let durationAlertEnabledKey = "durationAlertEnabled"
    private static let durationAlertThresholdKey = "durationAlertThresholdMinutes"
    /// 默认 36 小时。任务生命周期可以拉到天级（跨周自动结束能关、阈值也能配到天），
    /// 默认值跟着按天来。
    static let defaultDurationAlertThresholdMinutes = 36 * 60
    static let maxDurationAlertThresholdMinutes = 60 * 1440 + 24 * 60 + 60

    private convenience init() {
        let defaults = UserDefaults.standard
        self.init(storageURL: Self.defaultStorageURL(),
                  autoEndEnabled: defaults.object(forKey: "autoEndEnabled") as? Bool ?? true,
                  aiControlMode: defaults.string(forKey: Self.aiControlModeKey)
                      .flatMap(AIControlMode.init(rawValue:)) ?? .off,
                  startTimers: true,
                  durationAlertEnabled: defaults.object(forKey: Self.durationAlertEnabledKey) as? Bool ?? true,
                  durationAlertThresholdMinutes: defaults.object(forKey: Self.durationAlertThresholdKey) as? Int
                      ?? Self.defaultDurationAlertThresholdMinutes)
    }

    /// 可注入存储位置与开关的初始化入口，供测试构造隔离实例：
    /// 注入临时文件路径并跳过定时器，避免测试触碰真实用户数据与偏好设置。
    init(storageURL: URL,
         autoEndEnabled: Bool,
         aiControlMode: AIControlMode = .off,
         startTimers: Bool,
         durationAlertEnabled: Bool = true,
         durationAlertThresholdMinutes: Int = AppState.defaultDurationAlertThresholdMinutes,
         notifier: NotificationPresenting = SystemNotificationPresenter()) {
        self.storageURL = storageURL
        self.notifier = notifier
        // 注入实例（startTimers == false）视为隔离实例：偏好不落盘，避免污染真机设置
        self.persistsPreferences = startTimers
        showFloatingPanel = UserDefaults.standard.object(forKey: "showFloatingPanel") as? Bool ?? true
        self.autoEndEnabled = autoEndEnabled
        self.aiControlMode = aiControlMode
        self.durationAlertEnabled = durationAlertEnabled
        self.durationAlertThresholdMinutes = durationAlertThresholdMinutes
        lastCompletedViewedAt = Date()
        load()
        if startTimers { self.startTimers() }
    }

    // MARK: - 计算属性

    /// 当前任务 ID
    var activeTaskId: UUID? {
        todos.first(where: { $0.isActive })?.id
    }

    /// 排序后的待办列表：当前任务永远第一，其余非睡眠任务按挂起时长降序（suspendedSince 升序）。
    /// 睡眠任务一律沉底，且相互之间仍按 suspendedSince 稳定排列——其他任务怎么变顺序都影响不到它们。
    var sortedTodos: [TodoTask] {
        todos.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }
            if lhs.isSleeping != rhs.isSleeping {
                return !lhs.isSleeping
            }
            return lhs.suspendedSince < rhs.suspendedSince
        }
    }

    /// 是否存在「尚未查看」的跨周自动结束任务 → 入口图标上的红点。
    ///
    /// 刻意做成派生属性而不是一个标志位：启动时 `startTimers()` 会**立即**跑一次
    /// `autoEndStaleTasks()`，那一刻任何视图都还不存在——若是靠脉冲/`onChange` 去点亮，
    /// 这一波会永久丢失。派生则永远和 `completed` 保持一致，不会漂移。
    var hasUnseenAutoEnd: Bool {
        completed.contains { $0.autoEnded && $0.finishedAt > lastCompletedViewedAt }
    }

    /// 当前任务的单次会话时长
    func activeDuration(now: Date = Date()) -> TimeInterval {
        guard let task = todos.first(where: { $0.isActive }),
              let since = task.activeSince else { return 0 }
        return now.timeIntervalSince(since)
    }

    /// 某挂起任务的挂起时长
    func suspendedDuration(_ task: TodoTask, now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(task.suspendedSince)
    }

    // MARK: - 操作

    func addTask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(TodoTask(title: trimmed))
    }

    func renameTask(id: UUID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[idx].title = trimmed
    }

    /// 选中/切换当前任务；若再次点击当前任务则取消选中（回到挂起态）。
    /// 睡眠任务不能被直接激活：先按 `wakeTask` 语义唤醒，再设为当前。
    func activateTask(id: UUID) {
        let now = Date()

        // 睡眠任务先唤醒（视作重新开始，避免按原创建时间被跨周自动结束）
        if let idx = todos.firstIndex(where: { $0.id == id }), todos[idx].isSleeping {
            todos[idx].isSleeping = false
            todos[idx].createdAt = now
            todos[idx].suspendedSince = now
        }

        // 再次点击当前任务 → 取消选中
        if activeTaskId == id {
            for i in todos.indices where todos[i].isActive {
                todos[i].isActive = false
                todos[i].activeSince = nil
                todos[i].suspendedSince = now
            }
            return
        }

        // 原当前任务置为挂起
        for i in todos.indices where todos[i].isActive {
            todos[i].isActive = false
            todos[i].activeSince = nil
            todos[i].suspendedSince = now
        }

        // 新任务设为当前
        if let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].isActive = true
            todos[idx].activeSince = now
        }
    }

    // MARK: - 睡眠

    /// 转入睡眠：置灰并沉到列表最下方，不计时、不参与跨周自动结束。
    /// 若它是当前任务，同时取消其「当前在做」状态，维持 isSleeping 与 isActive 互斥。
    /// suspendedSince 保持不变，睡眠期间不影响它与其他睡眠任务的相对顺序。
    func sleepTask(id: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[idx].isSleeping = true
        if todos[idx].isActive {
            todos[idx].isActive = false
            todos[idx].activeSince = nil
        }
    }

    /// 唤醒：回到挂起状态，并当作「刚刚创建」——重置 createdAt 与 suspendedSince。
    /// 前者让它不会因原创建时间过早被跨周自动结束，后者让它按排序规则落到活跃组最下方。
    func wakeTask(id: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        todos[idx].isSleeping = false
        todos[idx].createdAt = now
        todos[idx].suspendedSince = now
    }

    // MARK: - 子任务操作

    /// 给指定父任务添加子任务（按添加顺序追加）
    func addSubtask(toParent id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[idx].subtasks.append(Subtask(title: trimmed))
    }

    /// 重命名子任务
    func renameSubtask(parentId: UUID, subtaskId: UUID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let pi = todos.firstIndex(where: { $0.id == parentId }),
              let si = todos[pi].subtasks.firstIndex(where: { $0.id == subtaskId }) else { return }
        todos[pi].subtasks[si].title = trimmed
    }

    /// 删除子任务
    func deleteSubtask(parentId: UUID, subtaskId: UUID) {
        guard let pi = todos.firstIndex(where: { $0.id == parentId }) else { return }
        todos[pi].subtasks.removeAll(where: { $0.id == subtaskId })
    }

    /// 切换子任务完成状态（勾选）
    func toggleSubtask(parentId: UUID, subtaskId: UUID) {
        guard let pi = todos.firstIndex(where: { $0.id == parentId }),
              let si = todos[pi].subtasks.firstIndex(where: { $0.id == subtaskId }) else { return }
        todos[pi].subtasks[si].isDone.toggle()
    }

    /// 结束任务 → 进入已完成列表（子任务跟随）。
    /// `source == .user` 时脉冲 +1，驱动入口图标抖动——只有用户自己点才抖。
    func finishTask(id: UUID, source: FinishSource) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        let task = todos.remove(at: idx)
        completed.append(CompletedTask(id: task.id,
                                       title: task.title,
                                       createdAt: task.createdAt,
                                       finishedAt: Date(),
                                       autoEnded: false,
                                       subtasks: task.subtasks))
        if source == .user { finishPulse += 1 }
    }

    /// 查看已完成列表：清掉入口图标上的红点。唯一的写入点。
    func markCompletedViewed() {
        lastCompletedViewedAt = Date()
    }

    /// 删除任务 → 彻底移除（不进入已完成列表）
    func deleteTask(id: UUID) {
        todos.removeAll(where: { $0.id == id })
    }

    /// 已完成任务放回待办
    func restoreTask(id: UUID) {
        guard let idx = completed.firstIndex(where: { $0.id == id }) else { return }
        let c = completed.remove(at: idx)
        todos.append(TodoTask(id: c.id,
                              title: c.title,
                              createdAt: Date(), // 重置创建时间，避免放回后被「跨自然周自动结束」立即完成
                              isActive: false,
                              activeSince: nil,
                              suspendedSince: Date(),
                              subtasks: c.subtasks))
    }

    /// 跨自然周自动结束：创建于上一个自然周（或更早）的待办任务自动结束。
    /// 受 `autoEndEnabled` 开关控制；关闭时不做任何处理（已结束的任务不会恢复）。
    /// 睡眠任务不参与——它们是「先放着」的任务，不该被跨周清走。
    func autoEndStaleTasks() {
        guard autoEndEnabled else { return }
        let now = Date()
        let stale = todos.filter { !$0.isSleeping && AutoEndScheduler.isStale($0, now: now) }
        guard !stale.isEmpty else { return }
        todos.removeAll(where: { !$0.isSleeping && AutoEndScheduler.isStale($0, now: now) })
        for task in stale {
            completed.append(CompletedTask(id: task.id,
                                           title: task.title,
                                           createdAt: task.createdAt,
                                           finishedAt: now,
                                           autoEnded: true,
                                           subtasks: task.subtasks))
        }
    }

    // MARK: - 任务时长提醒

    /// 检查并发送时长提醒。
    ///
    /// - Parameter firstObservation: 首次纳入观察（app 启动、或用户刚打开开关）。
    ///   此时已有的超时任务压成**一条汇总**；运行期则是每个新跨过阈值的任务单独提醒。
    func evaluateDurationAlerts(now: Date = Date(), firstObservation: Bool) {
        guard durationAlertEnabled, notifier.authorizationStatus == .authorized else { return }

        let candidates = DurationAlertScheduler.candidates(todos, now: now)
        // 懒剪枝：只保留仍然有效的键。已结束/删除的任务不再派生键会被丢掉，
        // 仍在同一状态段的键仍在派生集里、记忆不丢——不用去改 finish / delete 那些路径。
        alertedKeys.formIntersection(Set(candidates.map(\.key)))

        let threshold = TimeInterval(durationAlertThresholdMinutes * 60)
        let fresh = candidates.filter { $0.duration >= threshold && !alertedKeys.contains($0.key) }
        guard !fresh.isEmpty else { return }

        if firstObservation {
            // 汇总：把**每一个**超时任务的键都记下，这样 60 秒后运行期分支算出的 fresh
            // 就是空的——天然不会「启动发过汇总、随后又逐个重发」。
            let message = DurationAlertScheduler.summaryMessage()
            notifier.post(title: message.title, body: message.body)
        } else {
            for candidate in fresh {
                let message = DurationAlertScheduler.individualMessage(candidate)
                notifier.post(title: message.title, body: message.body)
            }
        }
        alertedKeys.formUnion(fresh.map(\.key))
    }

    /// 开关时长提醒。
    ///
    /// 打开时**在用户明确操作的上下文里**请求通知授权（官方推荐的时机）。
    /// completion 在主线程回调，回传最终是否开启——没通过时调用方要给出「去系统设置」的出路。
    /// 关闭不动时长配置，下次打开还是原来那个值。
    func setDurationAlertEnabled(_ enabled: Bool, completion: ((Bool) -> Void)? = nil) {
        guard enabled else {
            durationAlertEnabled = false
            completion?(true)
            return
        }
        notifier.requestAuthorization { [weak self] granted in
            guard let self else { return }
            self.durationAlertEnabled = granted
            if granted { self.evaluateDurationAlerts(firstObservation: true) }
            completion?(granted)
        }
    }

    /// 保存时长设置。**不改变开关状态**——开关是子菜单里独立的另一项，不替用户做决定。
    func setDurationAlertThreshold(minutes: Int) {
        durationAlertThresholdMinutes = minutes
        // 门槛变低可能让原本没超时的任务立刻超时，马上重算一次。注意已经在「已提醒」集合里的
        // 任务不会因为门槛降了而补发——这符合「同一段状态只提醒一次」。
        evaluateDurationAlerts(firstObservation: false)
    }

    // MARK: - 持久化

    private struct PersistedData: Codable {
        var todos: [TodoTask]
        var completed: [CompletedTask]
        /// 「已完成列表」上次被查看的时刻，用来判断红点
        var lastCompletedViewedAt: Date

        // 一旦写了任何一个 init，成员初始化器就不再合成，而 save() 正在用它——必须显式补上
        init(todos: [TodoTask], completed: [CompletedTask], lastCompletedViewedAt: Date) {
            self.todos = todos
            self.completed = completed
            self.lastCompletedViewedAt = lastCompletedViewedAt
        }

        private enum CodingKeys: String, CodingKey {
            case todos, completed, lastCompletedViewedAt
        }

        /// 兼容旧数据：缺字段时默认「此刻」——升级前早就存在的自动结束任务
        /// 不该背着一颗红点，否则用户会看到一颗不知道指向什么的提示。
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            todos = try container.decode([TodoTask].self, forKey: .todos)
            completed = try container.decode([CompletedTask].self, forKey: .completed)
            lastCompletedViewedAt = try container.decodeIfPresent(Date.self,
                                                                  forKey: .lastCompletedViewedAt) ?? Date()
        }
    }

    private static func defaultStorageURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("Attention", isDirectory: true)
                  .appendingPathComponent("tasks.json")
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        guard let data = try? Data(contentsOf: storageURL),
              let persisted = try? JSONDecoder().decode(PersistedData.self, from: data) else {
            todos = []
            completed = []
            return
        }

        // 计时重启清零：所有任务回到挂起态，单次会话计时归零
        todos = persisted.todos.map { t in
            var task = t
            task.isActive = false
            task.activeSince = nil
            // suspendedSince 保留持久化值，挂起时长跨重启连续（排序依据）
            return task
        }
        completed = persisted.completed
        // 回填水位线。这一步漏了编译器不会报错（属性有初值），
        // 结果是红点对所有自动结束任务常亮——最容易漏、后果最明显的一步。
        lastCompletedViewedAt = persisted.lastCompletedViewedAt
    }

    /// 偏好落盘的唯一出口，统一挡住隔离实例（见 `persistsPreferences`）
    private func persistPreference(_ value: Any, forKey key: String) {
        guard persistsPreferences else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func save() {
        let persisted = PersistedData(todos: todos,
                                      completed: completed,
                                      lastCompletedViewedAt: lastCompletedViewedAt)
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // 持久化失败静默处理，不阻塞主流程
        }
    }

    // MARK: - 计时

    private func startTimers() {
        // 每 30 秒刷新时长显示（分钟单位，低频避免分散注意力；加入 .common mode，菜单面板打开/拖拽时也能刷新）
        let tick = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick

        // 每分钟检查跨周自动结束
        let autoEnd = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.autoEndStaleTasks()
        }
        RunLoop.main.add(autoEnd, forMode: .common)
        autoEndTimer = autoEnd

        // 每 60 秒检查一次任务时长提醒。不复用上面 30 秒那个纯 UI tick（职责混淆），
        // 也不跟 autoEnd 挤一个 Timer（各自独立更好读）。
        let alerts = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluateDurationAlerts(firstObservation: false)
        }
        RunLoop.main.add(alerts, forMode: .common)
        durationAlertTimer = alerts

        // 启动时立即检查一次
        autoEndStaleTasks()

        // 启动时的时长提醒：先查授权（只查询、不弹窗），再按状态决定要不要补申请。
        //
        // 提醒**默认就是开启的**，如果从没问过用户（notDetermined），那道
        // `authorizationStatus == .authorized` 的守卫会让功能一路静默失效、用户还莫名其妙。
        // 所以这里补一次申请——既然默认开着，用户等于已经默认选择过了。
        notifier.refreshAuthorization { [weak self] in
            guard let self else { return }
            guard self.durationAlertEnabled, self.notifier.authorizationStatus == .notDetermined else {
                self.evaluateDurationAlerts(firstObservation: true)
                return
            }
            self.notifier.requestAuthorization { _ in
                self.evaluateDurationAlerts(firstObservation: true)
            }
        }
    }
}
