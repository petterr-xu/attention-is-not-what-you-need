import SwiftUI
import AppKit

/// 悬浮窗内容：折叠时显示单个圆形图标，展开时显示毛玻璃卡片
struct FloatingPanelView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.isPanelCollapsed {
            collapsedIcon
        } else {
            TodoListView(showsPanelToggle: false, showsCollapseButton: true, fixedSize: nil)
                .background(VisualEffectBackground())
                .overlay(alignment: .bottomTrailing) { resizeHandle }
        }
    }

    /// 右下角的缩放手柄。`padding(6)` 是为了躲开背景层那个 12pt 圆角（它是 masksToBounds 的，
    /// 贴太边会被裁掉）。折叠态是另一个视图，40×40 上没有手柄，也就没有东西会被误拖。
    private var resizeHandle: some View {
        PanelResizeHandle { size in
            AppState.shared.resizeFloatingPanel(to: size)
        }
        .frame(width: 18, height: 18)
        .padding(6)
    }

    /// 折叠态：单个圆形图标浮标，点击展开、拖动移动
    private var collapsedIcon: some View {
        Image(systemName: "checklist")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
            .background(Circle().fill(.regularMaterial))
            .overlay(alignment: .topTrailing) { unseenAutoEndDot }
            .contentShape(Circle())
            .onTapGesture {
                state.isPanelCollapsed = false
            }
            .help("点击展开，拖动移动")
    }

    /// 折叠成小浮标时也要能看到有未查看的自动结束任务——
    /// 这里渲染的不是 TodoListView，红点得单独加一份。
    @ViewBuilder
    private var unseenAutoEndDot: some View {
        if state.hasUnseenAutoEnd {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .offset(x: -4, y: 4)
        }
    }
}

/// 系统级毛玻璃背景（与菜单栏 MenuBarExtra 窗口一致的材质）
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
