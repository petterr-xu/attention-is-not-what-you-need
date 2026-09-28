import AppKit
import SwiftUI
import Combine

/// 负责创建与管理悬浮窗（NSPanel）
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var floatingPanel: NSPanel?
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    // 悬浮窗两种形态的固定尺寸
    private let expandedSize = NSSize(width: 360, height: 440)
    private let collapsedSize = NSSize(width: 40, height: 40)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupFloatingPanel()
        observeState()
        observeMenuBarPanel()
    }

    // MARK: - 悬浮窗

    private func setupFloatingPanel() {
        let rootView = FloatingPanelView()
            .environmentObject(AppState.shared)
        let hosting = DraggableHostingView(rootView: rootView)

        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: AppState.shared.isPanelCollapsed ? collapsedSize : expandedSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting
        panel.delegate = self

        self.panel = panel
        Self.floatingPanel = panel
        positionPanel()
        updatePanelSize()

        if AppState.shared.showFloatingPanel {
            panel.orderFrontRegardless()
        }
    }

    /// 定位到主屏右上角
    private func positionPanel() {
        guard let panel = panel,
              let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let frame = panel.frame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 24,
                                     y: visible.maxY - frame.height - 24))
    }

    /// 根据折叠状态调整窗口尺寸，保持顶部对齐
    private func updatePanelSize() {
        guard let panel = panel,
              let screen = panel.screen ?? NSScreen.main else { return }
        let target = AppState.shared.isPanelCollapsed ? collapsedSize : expandedSize
        let visible = screen.visibleFrame
        var frame = panel.frame
        // 左上角锚点：折叠/展开时保持左上角不变，浮标与收起按钮同侧，避免鼠标左右移动
        let anchor = NSPoint(x: frame.minX, y: frame.maxY)
        var origin = NSPoint(x: anchor.x, y: anchor.y - target.height)
        // 边界钳制，避免超出屏幕
        if origin.x < visible.minX { origin.x = visible.minX }
        if origin.y < visible.minY { origin.y = visible.minY }
        if origin.x + target.width > visible.maxX { origin.x = visible.maxX - target.width }
        if origin.y + target.height > visible.maxY { origin.y = visible.maxY - target.height }
        frame.size = target
        frame.origin = origin
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - 订阅状态

    private func observeState() {
        AppState.shared.$showFloatingPanel
            .sink { [weak self] show in
                guard let panel = self?.panel else { return }
                if show {
                    self?.positionPanel()
                    panel.orderFrontRegardless()
                } else {
                    panel.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        AppState.shared.$isPanelCollapsed
            .sink { [weak self] _ in
                self?.updatePanelSize()
            }
            .store(in: &cancellables)
    }

    // MARK: - 菜单栏面板联动

    /// 菜单栏面板打开（成为 key window）时，若悬浮窗处于展开态则自动折叠，避免两个列表同时出现
    private func observeMenuBarPanel() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            guard let keyWindow = NSApp.keyWindow else { return }
            // 菜单栏面板的 window level 为 statusBar(25)；alert 为 modalPanel(8)、悬浮窗为 floating(3)，
            // 用 level 精确区分，避免误触删除确认框
            if keyWindow !== Self.floatingPanel,
               keyWindow.level.rawValue >= NSWindow.Level.statusBar.rawValue,
               !AppState.shared.isPanelCollapsed {
                AppState.shared.isPanelCollapsed = true
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    /// 点击悬浮窗关闭按钮 → 仅隐藏并同步开关状态，不真正销毁窗口
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        AppState.shared.showFloatingPanel = false
        sender.orderOut(nil)
        return false
    }
}

// MARK: - 可拖动宿主视图

/// 让窗口背景可拖动（配合 isMovableByWindowBackground，系统级逐帧平滑拖动）
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

// MARK: - 可成为 Key 的悬浮面板

/// 无边框面板默认不能成为 key window，导致 TextField 无法输入；重写使其可成为 key
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
