import SwiftUI
import AppKit

/// 待办主视图：菜单栏面板与悬浮窗共用
struct TodoListView: View {
    @EnvironmentObject var state: AppState
    @State private var newTitle = ""
    @State private var showCompleted = false
    /// 抖动进度：整数脉冲驱动，每次 +1 就是一次抖动
    @State private var shakeTrigger: CGFloat = 0
    /// 是否显示底部「悬浮窗开关」（悬浮窗内不重复显示）
    var showsPanelToggle: Bool = true
    /// 是否显示标题栏折叠按钮（仅悬浮窗内显示）
    var showsCollapseButton: Bool = false
    /// 固定尺寸：菜单栏面板用（与 `popover.contentSize` 一致，不改）。悬浮窗传 nil，
    /// 让内容铺满窗口——窗口尺寸由 `AppState.floatingPanelSize` 决定，用户可以拖手柄调。
    var fixedSize: NSSize? = NSSize(width: 360, height: 440)

    /// 右下角缩放手柄占的横向空间（手柄 18 + 左右各 6 的 padding），底部行要给它让位
    private static let resizeHandleFootprint: CGFloat = 30
    @ObservedObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        sizedContent
            // 用户每手动结束一个任务就抖一次。用脉冲计数器而不是布尔：
            // 布尔 true→true 不算变化，onChange 不触发，第二次结束就不抖了。
            .onChange(of: state.finishPulse) { _ in
                withAnimation(.easeOut(duration: 0.5)) { shakeTrigger += 1 }
            }
    }

    @ViewBuilder
    private var sizedContent: some View {
        if let fixedSize {
            content.frame(width: fixedSize.width, height: fixedSize.height)
        } else {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var content: some View {
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
                    // 进入时清红点。改成「离开时清」会把查看期间新到的自动结束一并吞掉
                    if showCompleted { state.markCompletedViewed() }
                } label: {
                    Image(systemName: showCompleted ? "chevron.left" : "checkmark.circle")
                        .font(.callout)
                        .modifier(ShakeEffect(progress: shakeTrigger))
                        // overlay 写在 ShakeEffect 之后 → 红点不跟着抖
                        .overlay(alignment: .topTrailing) { unseenAutoEndDot }
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
                .padding(.leading, 14)
                // 这一支只出现在悬浮窗（有更新时）。右下角有缩放手柄，右侧要多留出它的位置，
                // 否则更新图标会顶在手柄上。
                .padding(.trailing, 14 + Self.resizeHandleFootprint)
                .padding(.vertical, 10)
            }
        }
    }

    /// 有未查看的跨周自动结束任务时，在入口图标上点一颗红点。
    /// 照 updateBadge 的范式：无提示时不渲染任何内容，因此不影响原有布局。
    @ViewBuilder
    private var unseenAutoEndDot: some View {
        // 已完成页里用户正看着内容，红点是噪音
        if !showCompleted && state.hasUnseenAutoEnd {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                // 偏移取 (1, -1) 而不是更靠外：再往外就飘成一颗「散落的点」，
                // 再往里会盖住图标本体，这个位置刚好贴着图标右上边缘
                .offset(x: 1, y: -1)
                .help("有跨周自动结束的任务，点进「已完成」查看")
        }
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
