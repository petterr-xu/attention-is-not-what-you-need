import Foundation
import Testing
@testable import Attention

/// 右键菜单在容器（悬浮窗面板 / 菜单栏 popover）内的落点。纯函数，翻转判断对不对全看这里。
@Suite("右键菜单落点几何")
struct MenuGeometryTests {
    /// 悬浮窗默认尺寸
    private let panel = NSRect(x: 0, y: 0, width: 360, height: 440)
    /// 单条目菜单实测约 65×34
    private let menu = NSSize(width: 120, height: 34)
    /// 任务行收起态高度
    private let rowHeight: CGFloat = 34

    private func row(bottom: CGFloat, x: CGFloat = 20, width: CGFloat = 320) -> NSRect {
        NSRect(x: x, y: bottom, width: width, height: rowHeight)
    }

    @Test("下方空间够：菜单顶边贴行底边，左边缘对齐")
    func placeBelowWhenRoomIsEnough() {
        let rect = MenuGeometry.place(menuSize: menu, rowRect: row(bottom: 200), panelBounds: panel)
        #expect(rect.maxY == 200, "菜单顶边应贴行底边")
        #expect(rect.minY == 200 - menu.height)
        #expect(rect.minX == 20)
        #expect(rect.size == menu)
    }

    @Test("下方放不下：翻到行的上方，菜单底边贴行顶边")
    func flipsAboveWhenBottomIsTight() {
        // 行底边离面板底边只剩 10pt，不够放 34pt 的菜单
        let rect = MenuGeometry.place(menuSize: menu, rowRect: row(bottom: 10), panelBounds: panel)
        #expect(rect.minY == 10 + rowHeight, "菜单底边应贴行顶边")
        #expect(rect.maxY <= panel.maxY)
    }

    @Test("上下都放得下时优先下方")
    func prefersBelowWhenBothSidesFit() {
        let rect = MenuGeometry.place(menuSize: menu, rowRect: row(bottom: 100), panelBounds: panel)
        #expect(rect.maxY == 100)
    }

    @Test("行贴着面板底边")
    func rowAtPanelBottomFlipsAbove() {
        let rect = MenuGeometry.place(menuSize: menu, rowRect: row(bottom: 0), panelBounds: panel)
        #expect(rect.minY == rowHeight)
        #expect(rect.maxY == rowHeight + menu.height)
    }

    @Test("行贴着面板顶边：上方没地方，仍旧弹在下方")
    func rowAtPanelTopStaysBelow() {
        let bottom = panel.maxY - rowHeight
        let rect = MenuGeometry.place(menuSize: menu, rowRect: row(bottom: bottom), panelBounds: panel)
        #expect(rect.maxY == bottom)
    }

    @Test("面板小到上下都放不下时，钳在面板内而不是溢出去")
    func clampsInsideWhenNeitherSideFits() {
        let tiny = NSRect(x: 0, y: 0, width: 280, height: 60)
        let rect = MenuGeometry.place(menuSize: menu, rowRect: row(bottom: 13), panelBounds: tiny)
        #expect(tiny.contains(rect))
    }

    @Test("行贴着右边：菜单往左让，右边缘不超出面板")
    func clampsXAtRightEdge() {
        let rect = MenuGeometry.place(menuSize: menu, rowRect: row(bottom: 200, x: 340), panelBounds: panel)
        #expect(rect.maxX == panel.maxX)
        #expect(rect.minX == panel.maxX - menu.width)
    }

    @Test("菜单比面板还宽时贴面板左边（横向溢出的下界）")
    func menuWiderThanPanelPinsToLeft() {
        let wide = NSSize(width: 400, height: 34)
        let rect = MenuGeometry.place(menuSize: wide, rowRect: row(bottom: 200, x: 40), panelBounds: panel)
        #expect(rect.minX == panel.minX)
    }
}
