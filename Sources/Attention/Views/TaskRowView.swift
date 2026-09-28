import SwiftUI
import AppKit

/// 单行待办任务：选中框切换当前任务，点击标题展开/收起子任务，右侧结束/重命名/删除
struct TaskRowView: View {
    @EnvironmentObject var state: AppState
    let task: TodoTask

    @State private var isEditing = false
    @State private var draftTitle = ""
    @State private var showDelete = false
    @State private var isExpanded = false
    @State private var newSubtaskTitle = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        if isExpanded {
            // 展开态：确认按钮留在信息行内，与子任务区共用一块底纹
            VStack(spacing: 4) {
                mainRow
                subtaskSection
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(rowBackgroundColor)
            )
        } else {
            // 收起态：确认按钮独立成块放在行尾，底纹颜色与左侧一致
            HStack(alignment: .top, spacing: 6) {
                mainRow
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(rowBackgroundColor)
                    )

                finishButton
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(rowBackgroundColor)
                    )
            }
        }
    }

    /// 结束任务按钮本体，外层容器由 body 按展开状态决定
    private var finishButton: some View {
        Button {
            state.finishTask(id: task.id)
        } label: {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("结束任务")
    }

    // MARK: - 主行

    private var mainRow: some View {
        HStack(spacing: 6) {
            // 当前任务指示（点击选中/切换）
            Button(action: { state.activateTask(id: task.id) }) {
                Image(systemName: task.isActive ? "play.circle.fill" : "circle")
                    .foregroundStyle(task.isActive ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(task.isActive ? "点击取消当前任务" : "点击设为当前任务")

            // 标题 / 编辑框（点击标题展开/收起子任务）
            if isEditing {
                TextField("任务名称", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($nameFieldFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
            } else {
                Text(task.title)
                    .fontWeight(task.isActive ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { isExpanded.toggle() }
                    .help(isExpanded ? "收起" : "展开全文与子任务")
            }

            Text(timeText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Button {
                if isEditing {
                    commitRename()
                } else {
                    startRename()
                }
            } label: {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isEditing ? "保存" : "重命名")

            if showDelete {
                Button {
                    state.deleteTask(id: task.id)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("确认删除")

                Button {
                    showDelete = false
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("取消删除")
            } else {
                Button {
                    showDelete = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除任务")
            }

            // 确认按钮始终在行尾：展开时留在行内共享底纹，收起时由 body 移到独立块
            if isExpanded {
                finishButton
            }
        }
    }

    // MARK: - 子任务区

    private var subtaskSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(task.subtasks) { subtask in
                SubtaskRowView(parentId: task.id, subtask: subtask)
            }

            HStack(spacing: 6) {
                TextField("type sub attention", text: $newSubtaskTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(addSubtask)
                Button(action: addSubtask) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(canAddSubtask ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canAddSubtask)
                .help("添加子任务")
            }
            .padding(.leading, 8)
        }
        .padding(.leading, 22)
    }

    private var canAddSubtask: Bool {
        !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addSubtask() {
        state.addSubtask(toParent: task.id, title: newSubtaskTitle)
        newSubtaskTitle = ""
    }

    // MARK: - 重命名

    private func startRename() {
        draftTitle = task.title
        isEditing = true
        nameFieldFocused = true
    }

    private func commitRename() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            state.renameTask(id: task.id, newTitle: trimmed)
        }
        isEditing = false
    }

    private func cancelRename() {
        isEditing = false
    }

    // MARK: - 其他

    private var timeText: String {
        let duration = task.isActive ? state.activeDuration() : state.suspendedDuration(task)
        let prefix = task.isActive ? "⏱ " : "⏸ "
        return prefix + TimeFormatter.string(from: duration)
    }

    /// 行底纹：当前在做 → 淡绿，挂起 → 淡红
    private var rowBackgroundColor: Color {
        task.isActive ? Color.green.opacity(0.18) : Color.red.opacity(0.12)
    }
}
