import SwiftUI
import AppKit

/// 右键菜单锚点。
///
/// SwiftUI 的 `.contextMenu` 在 macOS 上会把菜单弹在鼠标点击处，位置随点在行内的哪个位置而浮动；
/// 这里改为自己捕获右键，用 `NSMenu.popUp` 把菜单固定弹在本行正下方——下方放不下时翻到行的
/// 上方，落点由 `MenuGeometry` 钳在容器矩形内。
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
        guard let action, let window, let contentView = window.contentView else { return }

        let target = MenuActionTarget(action)
        menuTarget = target

        let item = NSMenuItem(title: title,
                              action: #selector(MenuActionTarget.invoke),
                              keyEquivalent: "")
        item.target = target

        let menu = NSMenu()
        menu.addItem(item)

        // 菜单矩形落到哪：优先行的正下方，下方空间不够就翻到行的上方，整体钳在容器内。
        // `NSMenu.popUp` 弹的是独立系统窗口，只保证不出**屏幕**、不知道容器的矩形——
        // 悬浮窗被调小之后行离底边很近，不自己算就会压着容器往外溢。
        //
        // 一律用**窗口基准坐标**（`convert(_:to: nil)`）：它一定未翻转、y 轴向上。
        // 不能图省事转到 contentView 坐标系——宿主是 `NSHostingView`，它是**翻转**的
        // （y 轴向下），「行下方」的算术会整个反过来。
        //
        // `menu.size` 在 popUp **之前**就已经是最终尺寸（单条目菜单实测 65×34 / 82×34，
        // 与菜单真正打开时读到的值一致，且随标题变化），所以不需要预估菜单高度。
        let menuRect = MenuGeometry.place(menuSize: menu.size,
                                          rowRect: convert(bounds, to: nil),
                                          panelBounds: contentView.convert(contentView.bounds, to: nil))

        // 锚点语义（见 NSMenu.h popUpMenuPositioningItem）：nil 时以菜单**左上角**对齐给定点，
        // 坐标取视图自身坐标系。本视图未翻转，菜单矩形的左上角就是锚点。
        let anchor = convert(NSPoint(x: menuRect.minX, y: menuRect.maxY), from: nil)
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
