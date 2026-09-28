import SwiftUI
import AppKit

/// 待办主视图：菜单栏面板与悬浮窗共用
struct TodoListView: View {
    @EnvironmentObject var state: AppState
    @State private var newTitle = ""
    @State private var showCompleted = false
    /// 是否显示底部「悬浮窗开关」（悬浮窗内不重复显示）
    var showsPanelToggle: Bool = true
    /// 是否显示标题栏折叠按钮（仅悬浮窗内显示）
    var showsCollapseButton: Bool = false
    @ObservedObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HStack {
                if showsCollapseButton {
                    Button {
                        state.isPanelCollapsed = true
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("折叠悬浮窗")
                }
                Text("You Need No Attention")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .italic()
                Spacer()
                Button {
                    showCompleted.toggle()
                } label: {
                    Image(systemName: showCompleted ? "chevron.left" : "checkmark.circle")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // 添加任务输入框（仅待办页显示）
            if !showCompleted {
                HStack(spacing: 6) {
                    TextField("type attention", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTask)
                    Button(action: addTask) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(canAdd ? Color.accentColor : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                    .help("添加任务")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            Divider()

            // 内容区
            Group {
                if showCompleted {
                    CompletedListView(onBack: { showCompleted = false })
                } else if state.todos.isEmpty {
                    emptyView
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(state.sortedTodos) { task in
                                TaskRowView(task: task)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底部一行：菜单栏面板是「显示悬浮窗」开关 + 更新提示，
            // 悬浮窗没有开关行、只放更新提示。两者都贴面板底部，位置一致。
            if showsPanelToggle {
                Divider()
                HStack(spacing: 0) {
                    Toggle("显示悬浮窗", isOn: $state.showFloatingPanel)
                        .toggleStyle(.checkbox)
                    Spacer()
                    updateBadge
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else if updateChecker.availableVersion != nil {
                Divider()
                HStack {
                    Spacer()
                    updateBadge
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 360, height: 440)
    }

    /// 有新版本时的提示图标。界面上不出现文字，版本号通过悬停提示给出。
    /// 无更新时不渲染任何内容，因此不影响原有布局。
    @ViewBuilder
    private var updateBadge: some View {
        if let version = updateChecker.availableVersion {
            Button {
                if let url = updateChecker.releaseURL {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("有新版本 \(version)，点击前往下载")
        }
    }

    private var canAdd: Bool {
        !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTask() {
        state.addTask(title: newTitle)
        newTitle = ""
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无待办")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
