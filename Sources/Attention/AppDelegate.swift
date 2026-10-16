import AppKit
import SwiftUI
import Combine
import AttentionControl

/// 负责创建与管理悬浮窗（NSPanel）
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var floatingPanel: NSPanel?
    static weak var menuBarPopover: NSPopover?
    private var panel: NSPanel?
    private var popover: NSPopover?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    /// 「保存」被接管期间，正在编辑的时长输入视图
    private var pendingDurationInput: DurationThresholdInputView?
    /// 本地控制通道（供 MCP 使用）。必须持强引用，否则被释放后 socket 会静默失效。
    private var controlServer: ControlServer?

    /// 悬浮窗折叠态的固定尺寸；展开态用 `AppState.floatingPanelSize`（用户可拖手柄调）
    private let collapsedSize = NSSize(width: 40, height: 40)
    /// 菜单栏面板尺寸，与 `TodoListView` 固定的 frame 一致
    private let popoverSize = NSSize(width: 360, height: 440)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 通知 delegate 要在任何可能与它交互的事情之前挂上（文档要求），
        // 而且它必须是强引用——delegate 是 weak，只放进 center 会被立刻释放。
        AppState.shared.notifier.installDelegate()

        setupStatusItem()
        setupPopover()
        setupFloatingPanel()
        observeState()
        startControlServer()
        UpdateChecker.shared.start()
    }

    // MARK: - 本地控制通道（MCP）

    /// 启动本地控制通道。
    ///
    /// 多实例（开发副本与已安装副本同时在跑）时第二个会 bind 失败，这里只记日志不崩溃——
    /// app 照常可用，只是没有控制通道。
    private func startControlServer() {
        let server = ControlServer(handlerQueue: .main) { command in
            // 必须在主线程执行：AppState 的所有变更都约定在主线程
            ControlDispatcher.dispatch(command, state: AppState.shared)
        }
        do {
            try server.start()
            controlServer = server
        } catch {
            NSLog("[Attention] 本地控制通道启动失败，AI 接口不可用：\(error)")
        }
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

        // 顺序：显示悬浮窗 / 自动结束跨周任务 / 任务时长提醒 / 允许 AI 控制 /
        //       配置 MCP 客户端 / 检查更新 / 关于 / 退出
        let floatingItem = NSMenuItem(
            title: "显示悬浮窗", action: #selector(toggleFloatingPanel), keyEquivalent: ""
        )
        floatingItem.target = self
        floatingItem.state = AppState.shared.showFloatingPanel ? .on : .off
        menu.addItem(floatingItem)

        menu.addItem(makeAutoEndItem())
        menu.addItem(makeDurationAlertItem())
        menu.addItem(makeAIControlItem())
        menu.addItem(makeMCPConfigItem())

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

    // MARK: - 任务时长提醒

    /// 「任务时长提醒」子菜单：一个开关 + 一个时长设置（与「允许 AI 控制」同为二级菜单）。
    ///
    /// 两项刻意分开——设置时长**不会**顺手把开关打开，也不替用户做决定。
    private func makeDurationAlertItem() -> NSMenuItem {
        let appState = AppState.shared
        let item = NSMenuItem(title: "任务时长提醒", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let toggle = NSMenuItem(title: "打开任务时长提醒",
                                action: #selector(toggleDurationAlert),
                                keyEquivalent: "")
        toggle.target = self
        toggle.state = appState.durationAlertEnabled ? .on : .off
        submenu.addItem(toggle)

        submenu.addItem(.separator())

        let duration = NSMenuItem(title: "时长设置…",
                                  action: #selector(changeDurationSetting),
                                  keyEquivalent: "")
        duration.target = self
        submenu.addItem(duration)

        item.submenu = submenu
        item.toolTip = "任务挂起或执行达到该时长后提醒一次；同一段状态只提醒一次，睡眠中的任务不参与。"
            + "\n当前：\(DurationAlertScheduler.describe(minutes: appState.durationAlertThresholdMinutes))"
            + (appState.durationAlertEnabled ? "" : "（提醒已关闭）")
        return item
    }

    @objc private func toggleDurationAlert() {
        let appState = AppState.shared
        guard !appState.durationAlertEnabled else {
            appState.setDurationAlertEnabled(false)
            return
        }
        appState.setDurationAlertEnabled(true) { [weak self] granted in
            guard !granted else { return }
            self?.presentNotificationPermissionHelp()
        }
    }

    /// 「时长设置…」：只改时长。开关没开的话**不替用户打开**，保存后提示去菜单里打开。
    @objc private func changeDurationSetting() {
        let appState = AppState.shared
        guard let minutes = promptForDuration(prefill: appState.durationAlertThresholdMinutes) else {
            return   // 取消
        }
        appState.setDurationAlertThreshold(minutes: minutes)
        guard !appState.durationAlertEnabled else { return }
        presentEnableHint()
    }

    private func presentEnableHint() {
        let alert = NSAlert()
        alert.messageText = "时长已保存"
        alert.informativeText = "不过「任务时长提醒」现在是关闭状态，"
            + "去「任务时长提醒 → 打开任务时长提醒」打开它才会生效。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// 权限被拒时给出可操作的出路，而不是让用户对着一个「打开了却没反应」的开关发愣。
    private func presentNotificationPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "通知权限被拒绝"
        alert.informativeText = "系统通知权限被拒绝，时长提醒发不出来。"
            + "到「系统设置 → 通知」里为 Attention 打开通知，再回来重新打开这个开关。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            AppState.shared.notifier.openSystemNotificationSettings()
        }
    }

    /// 让用户填提醒时长。返回 nil 表示取消。
    ///
    /// 「保存」的 action 被我们接管了：输入不合法时**不结束模态**，弹窗留在原地、出错的框标红
    /// （实时校验本来就在做，这里是兜底）。接管之后 NSAlert 自己的处理器不跑，
    /// 模态得靠 `stopModal` 自己收尾。
    private func promptForDuration(prefill: Int) -> Int? {
        let parts = DurationAlertScheduler.split(minutes: prefill)
        let input = DurationThresholdInputView(days: parts.days,
                                               hours: parts.hours,
                                               minutes: parts.minutes)

        let alert = NSAlert()
        alert.messageText = "任务时长提醒"
        alert.informativeText = "任务挂起或执行达到该时长后提醒一次"
        alert.accessoryView = input
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = input.firstField   // 打开即聚焦，省一次点击
        alert.buttons[0].target = self
        alert.buttons[0].action = #selector(confirmDuration(_:))

        pendingDurationInput = input
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        pendingDurationInput = nil

        return response == .alertFirstButtonReturn ? input.totalMinutes : nil
    }

    /// 接管后的「保存」：校验通过才结束模态，否则把出错的框标红、窗口不关
    @objc private func confirmDuration(_ sender: Any?) {
        guard let input = pendingDurationInput else { return }
        guard input.validationError == nil else {
            input.refreshValidation()
            return
        }
        NSApp.stopModal(withCode: .alertFirstButtonReturn)
    }

    // MARK: - AI 控制（MCP）

    /// 「允许 AI 控制」的三档子菜单。菜单每次右键重建，勾选态天然是最新的。
    private func makeAIControlItem() -> NSMenuItem {
        let item = NSMenuItem(title: "允许 AI 控制", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for mode in AIControlMode.allCases {
            let modeItem = NSMenuItem(title: mode.title,
                                      action: #selector(selectAIControlMode(_:)),
                                      keyEquivalent: "")
            modeItem.target = self
            modeItem.representedObject = mode.rawValue
            modeItem.state = AppState.shared.aiControlMode == mode ? .on : .off
            submenu.addItem(modeItem)
        }
        item.submenu = submenu
        item.toolTip = "控制本机 AI 工具（通过 MCP）能对待办做什么："
            + "「安全」只允许读取，「开放」允许读写。默认关闭。"
        return item
    }

    @objc private func selectAIControlMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AIControlMode(rawValue: raw) else { return }
        AppState.shared.aiControlMode = mode
    }

    private func makeMCPConfigItem() -> NSMenuItem {
        let item = NSMenuItem(title: "配置 MCP 客户端…",
                              action: #selector(showMCPConfiguration),
                              keyEquivalent: "")
        item.target = self
        return item
    }

    /// 桥接可执行文件的绝对路径。
    ///
    /// 必须由**运行中的 app 的 bundle** 现算：从 `build/Attention.app` 跑和从 `/Applications`
    /// 跑路径不同，写死会给出一个不存在的位置。
    private static var mcpHelperPath: String {
        Bundle.main.bundlePath + "/Contents/Helpers/attention-mcp"
    }

    private static var mcpJSONSnippet: String {
        """
        {
          "mcpServers": {
            "attention": {
              "type": "stdio",
              "command": "\(mcpHelperPath)",
              "args": []
            }
          }
        }
        """
    }

    /// Claude Code 的注册命令。`--scope user` 让它对所有项目生效——默认的 local 作用域只在
    /// 当前项目里可用，对一个全局待办应用来说不对。
    private static var mcpClaudeCommand: String {
        "claude mcp add --scope user attention -- \"\(mcpHelperPath)\""
    }

    @objc private func showMCPConfiguration() {
        let alert = NSAlert()
        alert.messageText = "配置 MCP 客户端"
        alert.informativeText = "把下面任一段加到你的 MCP 客户端里，AI 就能操作这个待办列表。"
        alert.accessoryView = MCPConfigAccessoryView.make(json: Self.mcpJSONSnippet,
                                                         command: Self.mcpClaudeCommand,
                                                         warning: Self.helperProblem())
        alert.addButton(withTitle: "复制 JSON 配置")
        alert.addButton(withTitle: "复制 Claude Code 命令")
        alert.addButton(withTitle: "关闭")
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            copy(Self.mcpJSONSnippet, describedAs: "MCP 配置 JSON")
        case .alertSecondButtonReturn:
            copy(Self.mcpClaudeCommand, describedAs: "Claude Code 命令")
        default:
            break
        }
    }

    /// helper 真有问题时才返回提示，正常路径下弹窗不掺任何噪音
    private static func helperProblem() -> MCPConfigAccessoryView.Warning? {
        let path = mcpHelperPath
        if !FileManager.default.isExecutableFile(atPath: path) {
            return .init(message: "⚠️ 包里缺少 helper——当前运行的可能是开发构建。"
                            + "先执行 ./build.sh，或从 dmg 安装。",
                         fixCommand: nil)
        }
        if isQuarantined(path) {
            return .init(message: "⚠️ helper 带有 quarantine 标记，客户端启动它时会被 Gatekeeper 拦下。"
                            + "在终端执行一次即可解除：",
                         fixCommand: "xattr -dr com.apple.quarantine \"\(path)\"")
        }
        return nil
    }

    /// helper 是否带 quarantine 标记（从 dmg 拷出来的文件会被打上）
    private static func isQuarantined(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.quarantinePropertiesKey])
        return values?.quarantineProperties != nil
    }

    /// 剪贴板操作本身没有任何视觉反馈，用户无法确认是否生效，所以补一句确认。
    private func copy(_ text: String, describedAs description: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let alert = NSAlert()
        alert.messageText = "已复制到剪贴板"
        alert.informativeText = "\(description)已复制，粘贴到对应位置即可。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
            contentRect: NSRect(origin: .zero,
                                size: AppState.shared.isPanelCollapsed
                                    ? collapsedSize
                                    : AppState.shared.floatingPanelSize),
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

    /// 根据折叠状态调整窗口尺寸，保持左上角对齐。
    ///
    /// `isCollapsed` / `size` 一律**从订阅里传进来**，不在函数里回读 `AppState`——
    /// `@Published` 是在 **willSet** 里投递的：sink 收到的是新值，但此刻回读同一个属性
    /// 拿到的还是**旧值**。回读的写法会导致「松手后窗口被打回拖之前的大小」这类诡异现象
    /// （折叠态回读到旧值时会算成展开尺寸，只是恰好被宿主视图按内容固有尺寸兜住了）。
    /// 不传参数时（直接调用）才回读，那是安全的。
    private func updatePanelSize(isCollapsed: Bool? = nil, size: NSSize? = nil) {
        guard let panel = panel,
              let screen = panel.screen ?? NSScreen.main else { return }
        let collapsed = isCollapsed ?? AppState.shared.isPanelCollapsed
        let desired = size ?? AppState.shared.floatingPanelSize
        // 左上角锚点：折叠/展开时保持左上角不动，浮标与收起按钮同侧，避免鼠标左右移动
        let anchor = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        // 展开态用用户调过的尺寸（在大屏上调过、换到小屏也会被屏幕钳住）；折叠态是固定的小浮标
        let target = collapsed ? collapsedSize : desired
        panel.setFrame(PanelGeometry.frame(anchoringTopLeft: anchor,
                                           size: target,
                                           inVisible: screen.visibleFrame),
                       display: true, animate: false)
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
