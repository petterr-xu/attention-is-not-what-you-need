import AppKit
import SwiftUI

/// 悬浮窗右下角的缩放手柄。
///
/// **必须用 AppKit 而不是 SwiftUI 手势**：窗口背景是 `mouseDownCanMoveWindow = true`
/// （配合 `isMovableByWindowBackground` 实现「拖空白处移动窗口」）。那种情况下视图收得到
/// `mouseDown` / `mouseUp`（所以行内按钮点得动），但 **`mouseDragged` 会被窗口移动机制吃掉**
/// ——拖拽手势根本收不到事件。这里明确返回 `false`，让手柄在命中测试里压过背景拖动，
/// 才能拿到完整的拖拽序列。（`DraggableHostingView` 是反过来用同一个属性。）
struct PanelResizeHandle: NSViewRepresentable {
    /// 拖拽结束、松手时把最终尺寸交出去
    let onCommit: (NSSize) -> Void

    func makeNSView(context: Context) -> ResizeHandleView {
        let view = ResizeHandleView()
        view.onCommit = onCommit
        return view
    }

    func updateNSView(_ nsView: ResizeHandleView, context: Context) {
        nsView.onCommit = onCommit
    }
}

final class ResizeHandleView: NSView {
    var onCommit: ((NSSize) -> Void)?

    private var startSize: NSSize = .zero
    private var startAnchor: NSPoint = .zero
    private var startMouse: NSPoint = .zero
    private var currentSize: NSSize = .zero

    /// 关键：压过背景拖动。窗口是按命中到的**最深层视图**决定要不要整窗拖动的。
    override var mouseDownCanMoveWindow: Bool { false }

    /// 非激活面板上第一次点击也要直接生效，不用先点一下唤醒
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        // AppKit 没有公开的「对角缩放」光标，用十字代替
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        // macOS 窗口右下角那种：两道**平行**斜线（斜率都是 1，只差一个垂直偏移），
        // 贴着右下角。非翻转视图里右下角是 (maxX, 0)，所以线往上右方向走。
        let strokes: [(from: NSPoint, to: NSPoint)] = [
            (NSPoint(x: bounds.maxX - 13, y: 2), NSPoint(x: bounds.maxX - 2, y: 13)),
            (NSPoint(x: bounds.maxX - 7, y: 2), NSPoint(x: bounds.maxX - 2, y: 7))
        ]
        NSColor.secondaryLabelColor.setStroke()
        for stroke in strokes {
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.move(to: stroke.from)
            path.line(to: stroke.to)
            path.stroke()
        }
    }

    // MARK: - 拖拽

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startSize = window.frame.size
        // 锚点取一次就够：拖拽全程都从**起点**重算，窗口中途被屏幕钳着滑动也不会累积漂移
        startAnchor = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        currentSize = startSize
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let screen = window.screen else { return }
        currentSize = PanelGeometry.resized(start: startSize,
                                            startMouse: startMouse,
                                            currentMouse: NSEvent.mouseLocation)
        // 拖拽期间**只改窗口**，不写 AppState：每帧发布会让 SwiftUI 重渲染，
        // 一旦这个 NSView 在拖拽中途被销毁，拖动就断了。内容本身是弹性布局，跟着窗口走。
        // 几何与松手提交共用 `PanelGeometry.frame`，避免两条规则在接缝处对不上。
        window.setFrame(PanelGeometry.frame(anchoringTopLeft: startAnchor,
                                            size: currentSize,
                                            inVisible: screen.visibleFrame),
                        display: true, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        // 只是点了一下手柄、没有真的拖动：不要提交，否则会把「当前窗口尺寸」写进偏好，
        // 而窗口尺寸可能已被屏幕钳过、与用户存的尺寸不同（点一下就把偏好改掉了）
        guard currentSize != startSize else { return }
        onCommit?(currentSize)
    }
}
