import Foundation

/// 悬浮窗尺寸的几何计算。纯函数、不碰窗口，所以能直接单测。
enum PanelGeometry {
    /// 宽度下限 280：行内固定占位（选中圆点 + 时长文字 + 重命名 + 删除 + 收起态行尾那个
    /// 结束块 + 各间距与内边距）约 223pt，这个宽度还能给标题留 100pt 左右。
    /// 高度下限 180 = 标题栏 + 输入行 + 两行任务 + 余量。
    /// 这是**用户能拖到的范围**，只在 `clamp` 里用；折叠态那个 40×40 是固定 UI 状态，
    /// 不走这个下限（见 `frame`）。
    static let minSize = NSSize(width: 280, height: 180)
    /// 绝对上限；实际应用时还会按当前屏幕再钳一次
    static let maxSize = NSSize(width: 1000, height: 1200)
    /// 默认尺寸，与菜单栏面板保持一致
    static let defaultSize = NSSize(width: 360, height: 440)

    /// 把用户给的尺寸钳进 [minSize, maxSize]。手柄拖出来的尺寸、落盘读回来的尺寸都过这里。
    static func clamp(_ size: NSSize) -> NSSize {
        guard size.width.isFinite, size.height.isFinite else { return defaultSize }
        return NSSize(width: min(max(size.width, minSize.width), maxSize.width),
                      height: min(max(size.height, minSize.height), maxSize.height))
    }

    /// 用**绝对鼠标位置**算新尺寸：起点尺寸 + 位移。
    ///
    /// 刻意不用 `event.deltaX/deltaY` 去累计——拖动过程里窗口一直在变，丢一个拖动事件
    /// 就会永久偏移；每次都从起点重算的绝对坐标会自愈。
    ///
    /// 屏幕坐标 y 轴向上，所以往下拖（y 变小）高度是变大的：`start.height - (now.y - start.y)`。
    static func resized(start: NSSize,
                        startMouse: NSPoint,
                        currentMouse: NSPoint) -> NSSize {
        clamp(NSSize(width: start.width + (currentMouse.x - startMouse.x),
                     height: start.height - (currentMouse.y - startMouse.y)))
    }

    /// 把「左上角锚点 + 一个**已经定好的**尺寸」落成一个合法的窗口 frame。
    ///
    /// 尺寸只按屏幕钳（装不下才缩），**不按 `minSize` 抬升**：传进来的尺寸是调用方定死的
    /// ——用户的尺寸早就在 `clamp` 里钳过了，折叠态那个 40×40 更是固定 UI 状态，被抬到
    /// 280×180 会让「点折叠按钮」先缩成中等大小、再由宿主视图缩成小浮标，看着就是
    /// 「先缩小、再收起」。
    ///
    /// origin 再钳回屏幕内：右边/上边放不下就贴着屏幕边缘往左/往下让，但不越过屏幕左边/
    /// 下边（窗口始终整个可见）。**拖拽期间和松手提交都必须走这一条**，两条规则在接缝处
    /// 会对不上——面板挪到屏幕边缘附近再拖，松手就会横向或纵向跳一段。
    static func frame(anchoringTopLeft anchor: NSPoint, size: NSSize, inVisible visible: NSRect) -> NSRect {
        let size = NSSize(width: min(size.width, visible.width),
                          height: min(size.height, visible.height))
        var origin = NSPoint(x: anchor.x, y: anchor.y - size.height)
        origin.x = min(origin.x, visible.maxX - size.width)
        origin.y = min(origin.y, visible.maxY - size.height)
        origin.x = max(origin.x, visible.minX)
        origin.y = max(origin.y, visible.minY)
        return NSRect(origin: origin, size: size)
    }
}
