import Foundation
import Combine

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
        didSet { UserDefaults.standard.set(showFloatingPanel, forKey: "showFloatingPanel") }
    }
    /// 悬浮窗是否折叠成小条
    @Published var isPanelCollapsed = false

    private var tickTimer: Timer?
    private var autoEndTimer: Timer?
    private var isLoading = false
    private let storageURL: URL

    private init() {
        storageURL = Self.defaultStorageURL()
        showFloatingPanel = UserDefaults.standard.object(forKey: "showFloatingPanel") as? Bool ?? true
        load()
        startTimers()
    }

    // MARK: - 计算属性

    /// 当前任务 ID
    var activeTaskId: UUID? {
        todos.first(where: { $0.isActive })?.id
    }

    /// 排序后的待办列表：当前任务永远第一，其余按挂起时长降序（suspendedSince 升序）
    var sortedTodos: [TodoTask] {
        todos.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }
            return lhs.suspendedSince < rhs.suspendedSince
        }
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

    /// 选中/切换当前任务；若再次点击当前任务则取消选中（回到挂起态）
    func activateTask(id: UUID) {
        let now = Date()

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

    /// 结束任务 → 进入已完成列表（子任务跟随）
    func finishTask(id: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        let task = todos.remove(at: idx)
        completed.append(CompletedTask(id: task.id,
                                       title: task.title,
                                       createdAt: task.createdAt,
                                       finishedAt: Date(),
                                       autoEnded: false,
                                       subtasks: task.subtasks))
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

    /// 跨自然周自动结束：创建于上一个自然周（或更早）的待办任务自动结束
    func autoEndStaleTasks() {
        let now = Date()
        let stale = todos.filter { AutoEndScheduler.isStale($0, now: now) }
        guard !stale.isEmpty else { return }
        todos.removeAll(where: { AutoEndScheduler.isStale($0, now: now) })
        for task in stale {
            completed.append(CompletedTask(id: task.id,
                                           title: task.title,
                                           createdAt: task.createdAt,
                                           finishedAt: now,
                                           autoEnded: true,
                                           subtasks: task.subtasks))
        }
    }

    // MARK: - 持久化

    private struct PersistedData: Codable {
        var todos: [TodoTask]
        var completed: [CompletedTask]
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
    }

    private func save() {
        let persisted = PersistedData(todos: todos, completed: completed)
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

        // 启动时立即检查一次
        autoEndStaleTasks()
    }
}
