import Foundation

/// 右键菜单在悬浮窗内的落点。纯几何、不碰 AppKit，所以能直接单测。
///
/// 坐标系一律是**容器内容坐标系**（悬浮窗的面板 / 菜单栏 popover 的内容矩形）：未翻转、y 轴向上。
enum MenuGeometry {
    /// 菜单矩形该落在哪。矩形**左上角**即 `NSMenu.popUp(positioning:at:in:)` 的锚点。
    ///
    /// 规则：**下方优先**（菜单顶边贴行底边，与右键菜单一贯的位置一致）；下方空间不够就
    /// **翻到行的上方**（菜单底边贴行顶边）；容器小到上下都放不下时直接钳进去，保证菜单整体
    /// 可见——菜单比容器还高时才允许向上溢出，而单条目菜单只有 34pt 高，实际到不了这一步。
    ///
    /// 横向只钳制、不翻转：`popUp` 只有「左上角对齐给定点」一种语义，而且单条目菜单
    /// （sleep ≈ 65pt）永远比容器窄，钳制纯粹是防御。
    static func place(menuSize: NSSize, rowRect: NSRect, panelBounds: NSRect) -> NSRect {
        let height = menuSize.height
        let top: CGFloat
        if rowRect.minY - height >= panelBounds.minY {
            top = rowRect.minY
        } else if rowRect.maxY + height <= panelBounds.maxY {
            top = rowRect.maxY + height
        } else {
            top = min(max(rowRect.minY, panelBounds.minY + height), panelBounds.maxY)
        }
        let x = max(min(rowRect.minX, panelBounds.maxX - menuSize.width), panelBounds.minX)
        return NSRect(x: x, y: top - height, width: menuSize.width, height: height)
    }
}
