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
                            completedRow(task)
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

    private func completedRow(_ task: CompletedTask) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if task.autoEnded {
                    Text("跨周自动结束")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
