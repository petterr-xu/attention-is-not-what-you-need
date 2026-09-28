import SwiftUI
import AppKit

/// 单行子任务：多选勾选标记完成（仅变灰），支持改名/删除，无计时
struct SubtaskRowView: View {
    @EnvironmentObject var state: AppState
    let parentId: UUID
    let subtask: Subtask

    @State private var isEditing = false
    @State private var draftTitle = ""
    @State private var showDelete = false
    @State private var isTitleExpanded = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // 多选勾选：标记完成
            Button(action: { state.toggleSubtask(parentId: parentId, subtaskId: subtask.id) }) {
                Image(systemName: subtask.isDone ? "checkmark.square.fill" : "square")
                    .foregroundStyle(subtask.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(subtask.isDone ? "取消完成" : "标记完成")

            // 标题 / 编辑框
            if isEditing {
                TextField("子任务名称", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($nameFieldFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
            } else {
                Text(subtask.title)
                    .foregroundStyle(subtask.isDone ? Color.secondary : Color.primary)
                    .lineLimit(isTitleExpanded ? nil : 1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { isTitleExpanded.toggle() }
                    .help(isTitleExpanded ? "收起" : "展开全文")
            }

            Button {
                if isEditing { commitRename() } else { startRename() }
            } label: {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isEditing ? "保存" : "重命名")

            if showDelete {
                Button {
                    state.deleteSubtask(parentId: parentId, subtaskId: subtask.id)
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
                .help("删除子任务")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.08))
        )
    }

    private func startRename() {
        draftTitle = subtask.title
        isEditing = true
        nameFieldFocused = true
    }

    private func commitRename() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            state.renameSubtask(parentId: parentId, subtaskId: subtask.id, newTitle: trimmed)
        }
        isEditing = false
    }

    private func cancelRename() {
        isEditing = false
    }
}
