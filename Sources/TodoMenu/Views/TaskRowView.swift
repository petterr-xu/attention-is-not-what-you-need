import SwiftUI
import AppKit

/// 单行待办任务：点击选中/切换当前任务，右侧结束/重命名/删除
struct TaskRowView: View {
    @EnvironmentObject var state: AppState
    let task: TodoTask

    @State private var isEditing = false
    @State private var draftTitle = ""
    @State private var showDelete = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // 当前任务指示（点击选中/切换）
            Button(action: { state.activateTask(id: task.id) }) {
                Image(systemName: task.isActive ? "play.circle.fill" : "circle")
                    .foregroundStyle(task.isActive ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(task.isActive ? "点击取消当前任务" : "点击设为当前任务")

            // 标题 / 编辑框
            if isEditing {
                TextField("任务名称", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($nameFieldFocused)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
            } else {
                Text(task.title)
                    .fontWeight(task.isActive ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
                    .onTapGesture { state.activateTask(id: task.id) }
            }

            Spacer()

            Text(timeText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Button {
                state.finishTask(id: task.id)
            } label: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("结束任务")

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

            Button {
                showDelete = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("删除任务")
            .alert("删除任务？", isPresented: $showDelete) {
                Button("删除", role: .destructive) { state.deleteTask(id: task.id) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("「\(task.title)」将被永久删除。")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

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

    private var timeText: String {
        let duration = task.isActive ? state.activeDuration() : state.suspendedDuration(task)
        let prefix = task.isActive ? "⏱ " : "⏸ "
        return prefix + TimeFormatter.string(from: duration)
    }
}
