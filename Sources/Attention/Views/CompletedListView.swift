import SwiftUI
import AppKit

/// 已完成任务列表：默认展示当天结束的，可查看全部、可放回待办
struct CompletedListView: View {
    @EnvironmentObject var state: AppState
    @State private var showAll = false
    let onBack: () -> Void

    /// 过滤：默认当天结束，showAll 时全部
    private var filtered: [CompletedTask] {
        if showAll { return state.completed }
        return state.completed.filter { Calendar.current.isDateInToday($0.finishedAt) }
    }

    /// 按结束时间倒序（最新结束在前）
    private var sorted: [CompletedTask] {
        filtered.sorted { $0.finishedAt > $1.finishedAt }
    }

    var body: some View {
        VStack(spacing: 8) {
            if sorted.isEmpty {
                Spacer()
                Text(showAll ? "暂无已完成任务" : "今天暂无已完成任务")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(sorted) { task in
                            CompletedTaskRowView(task: task)
                        }
                    }
                    .padding(8)
                }
            }

            HStack {
                Toggle("查看全部", isOn: $showAll)
                    .toggleStyle(.checkbox)
                Spacer()
            }
            .padding(.horizontal)
        }
    }
}

/// 单行已完成任务：点击标题可展开查看子任务（只读），右侧放回待办
private struct CompletedTaskRowView: View {
    @EnvironmentObject var state: AppState
    let task: CompletedTask
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if !task.subtasks.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(task.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if !task.subtasks.isEmpty { isExpanded.toggle() } }
                if task.autoEnded {
                    Text("跨周自动结束")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(task.finishedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    state.restoreTask(id: task.id)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("放回待办")
            }

            if isExpanded && !task.subtasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.subtasks) { subtask in
                        HStack(spacing: 6) {
                            Image(systemName: subtask.isDone ? "checkmark.square.fill" : "square")
                                .foregroundStyle(.secondary)
                            Text(subtask.title)
                                .foregroundStyle(subtask.isDone ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.08))
                        )
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
