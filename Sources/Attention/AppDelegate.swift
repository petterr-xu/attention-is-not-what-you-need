import AppKit
import SwiftUI
import Combine

/// 负责创建与管理悬浮窗（NSPanel）
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var floatingPanel: NSPanel?
    static weak var menuBarPopover: NSPopover?
    private var panel: NSPanel?
    private var popover: NSPopover?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    // 悬浮窗两种形态的固定尺寸
    private let expandedSize = NSSize(width: 360, height: 440)
    private let collapsedSize = NSSize(width: 40, height: 40)
    /// 菜单栏面板尺寸，与 TodoListView 内部固定的 frame 一致
    private let popoverSize = NSSize(width: 360, height: 440)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupFloatingPanel()
        observeState()
        UpdateChecker.shared.start()
    }

    // MARK: - 菜单栏图标与面板

    /// 菜单栏图标：左键开合待办面板，右键弹功能菜单
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Attention")
            image?.isTemplate = true          // 跟随菜单栏深浅色自动反色
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    /// 待办面板：复用 TodoListView，改由 popover 承载
    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient         // 点击外部自动收起
        popover.contentSize = popoverSize
        popover.contentViewController = NSHostingController(
            rootView: TodoListView().environmentObject(AppState.shared)
        )
        // 必须自己持强引用：menuBarPopover 是 weak，只存那里的话函数一返回就被释放，
        // 表现为左键点击菜单栏图标毫无反应。
        self.popover = popover
        Self.menuBarPopover = popover
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // 与悬浮窗互斥：面板要展开时把悬浮窗折成浮标，两个列表不同时出现
        if !AppState.shared.isPanelCollapsed {
            AppState.shared.isPanelCollapsed = true
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - 右键菜单

    /// 每次右键时重新构建，保证「显示悬浮窗」的勾选状态是最新的。
    /// 注意不要常驻挂在 statusItem.menu 上，否则左键也会弹菜单。
    private func showContextMenu() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()

        // 顺序：显示悬浮窗 / 自动结束跨周任务 / 检查更新 / 关于 / 退出
        let floatingItem = NSMenuItem(
            title: "显示悬浮窗", action: #selector(toggleFloatingPanel), keyEquivalent: ""
        )
        floatingItem.target = self
        floatingItem.state = AppState.shared.showFloatingPanel ? .on : .off
        menu.addItem(floatingItem)

        menu.addItem(makeAutoEndItem())

        let updateItem = NSMenuItem(
            title: "检查更新", action: #selector(checkForUpdates), keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        let aboutItem = NSMenuItem(
            title: "关于 Attention", action: #selector(showAbout), keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // 不设 target，沿 responder chain 交给 NSApp
        menu.addItem(NSMenuItem(
            title: "退出 Attention",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    /// 「自动结束跨周任务」开关。
    /// 功能说明走 toolTip 而不是行内问号——保持标准菜单项样式，悬停高亮、对齐、
    /// 点完自动关闭都交给系统，不用自己复刻菜单项的绘制与交互。
    private func makeAutoEndItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "自动结束跨周任务",
            action: #selector(toggleAutoEnd),
            keyEquivalent: ""
        )
        item.target = self
        item.state = AppState.shared.autoEndEnabled ? .on : .off
        item.toolTip = "创建于上一个自然周（或更早）的任务，跨周后会自动结束并移入「已完成」列表；"
            + "被自动结束的任务可在已完成列表里手动「放回」"
        return item
    }

    @objc private func toggleAutoEnd() {
        AppState.shared.autoEndEnabled.toggle()
    }

    @objc private func toggleFloatingPanel() {
        AppState.shared.showFloatingPanel.toggle()
    }

    @objc private func checkForUpdates() {
        Task { @MainActor in
            let newVersion = await UpdateChecker.shared.checkManually()
            let alert = NSAlert()
            if let newVersion {
                alert.messageText = "发现新版本 \(newVersion)"
                alert.informativeText = "当前版本 \(Self.appVersion)"
                alert.addButton(withTitle: "前往下载")
                alert.addButton(withTitle: "稍后")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn,
                   let url = UpdateChecker.shared.releaseURL {
                    NSWorkspace.shared.open(url)
                }
            } else {
                alert.messageText = "已是最新版本"
                alert.informativeText = "当前版本 \(Self.appVersion)"
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Attention"
        alert.informativeText = """
            版本 \(Self.appVersion)

            Attention Is Not What You Need —— 把「记住要做什么」这件事交给工具。
            """
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// 应用版本，来自 Info.plist
    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
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

    /// 收起菜单栏面板。点击悬浮窗时调用——悬浮窗是 nonactivatingPanel，点击它不会让应用失活，
    /// popover 的 transient 行为不会触发，需要主动关闭，否则两个列表会同时出现。
    static func dismissMenuBarPanel() {
        menuBarPopover?.performClose(nil)
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

    /// 点击悬浮窗时收起菜单栏面板，避免两个列表同时出现。
    ///
    /// 不能依赖系统的自动关闭：悬浮窗是 nonactivatingPanel，点击不会让应用失活；
    /// 又因为 becomesKeyOnlyIfNeeded，点击列表空白处时窗口根本不会成为 key window、
    /// 不会发生 key window 切换，「点第二下才关」就是这么来的。这里直接主动收起。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            AppDelegate.dismissMenuBarPanel()
        }
        super.sendEvent(event)
    }
}
