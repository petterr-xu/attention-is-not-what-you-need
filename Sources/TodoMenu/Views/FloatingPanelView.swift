import SwiftUI
import AppKit

/// 悬浮窗内容：折叠时显示单个圆形图标，展开时显示毛玻璃卡片
struct FloatingPanelView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.isPanelCollapsed {
            collapsedIcon
        } else {
            TodoListView(showsPanelToggle: false, showsCollapseButton: true)
                .background(VisualEffectBackground())
        }
    }

    /// 折叠态：单个圆形图标浮标，点击展开、拖动移动
    private var collapsedIcon: some View {
        Image(systemName: "checklist")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
            .background(Circle().fill(.regularMaterial))
            .contentShape(Circle())
            .onTapGesture {
                state.isPanelCollapsed = false
            }
            .help("点击展开，拖动移动")
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
