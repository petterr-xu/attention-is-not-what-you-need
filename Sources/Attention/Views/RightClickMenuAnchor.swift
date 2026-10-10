import SwiftUI
import AppKit

/// 右键菜单锚点。
///
/// SwiftUI 的 `.contextMenu` 在 macOS 上会把菜单弹在鼠标点击处，位置随点在行内的哪个位置而浮动；
/// 这里改为自己捕获右键，用 `NSMenu.popUp` 把菜单固定弹在本行正下方。
struct RightClickMenuAnchor: NSViewRepresentable {
    let title: String
    let action: () -> Void

    func makeNSView(context: Context) -> RightClickCatcherView {
        let view = RightClickCatcherView()
        view.title = title
        view.action = action
        return view
    }

    func updateNSView(_ nsView: RightClickCatcherView, context: Context) {
        nsView.title = title
        nsView.action = action
    }
}

/// 只接管右键的透明视图：其余事件（左键、滚轮、悬停）一律穿透，
/// 不影响行内的选中、展开、重命名输入框与各按钮。
final class RightClickCatcherView: NSView {
    var title: String = ""
    var action: (() -> Void)?

    /// 菜单项目标。NSMenuItem 对 target 是弱引用，需自己持有到菜单关闭。
    private var menuTarget: MenuActionTarget?

    /// 只有右键命中本视图，其余事件返回 nil 让下层 SwiftUI 视图正常响应
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let action else { return }

        let target = MenuActionTarget(action)
        menuTarget = target

        let item = NSMenuItem(title: title,
                              action: #selector(MenuActionTarget.invoke),
                              keyEquivalent: "")
        item.target = target

        let menu = NSMenu()
        menu.addItem(item)

        // 锚点语义（见 NSMenu.h popUpMenuPositioningItem）：nil 时以菜单左上角对齐给定点，
        // 坐标取视图自身坐标系。本视图未翻转，y=0 即行的底边，菜单因此落在整行正下方。
        let anchor = NSPoint(x: 0, y: 0)
        menu.popUp(positioning: nil, at: anchor, in: self)

        // popUp 同步阻塞到菜单关闭，返回后即可释放 target
        menuTarget = nil
    }
}

/// 把菜单项动作以闭包形式挂到 NSMenuItem 上（NSMenuItem 的 action 需要 target/selector）
final class MenuActionTarget: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invoke() {
        handler()
    }
}
