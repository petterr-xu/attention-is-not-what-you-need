import Combine
import Foundation
import Testing
@testable import Attention

/// 悬浮窗尺寸的几何计算。纯函数，拖拽能不能算对全看这里。
@Suite("悬浮窗尺寸几何")
struct PanelGeometryTests {
    @Test("小于下限钳到下限，大于上限钳到上限")
    func clampBounds() {
        #expect(PanelGeometry.clamp(NSSize(width: 10, height: 10)) == PanelGeometry.minSize)
        #expect(PanelGeometry.clamp(NSSize(width: 9999, height: 9999)) == PanelGeometry.maxSize)

        let normal = NSSize(width: 400, height: 500)
        #expect(PanelGeometry.clamp(normal) == normal)
    }

    @Test("0 / 负数都被钳到下限")
    func clampNonPositive() {
        #expect(PanelGeometry.clamp(NSSize(width: 0, height: 0)) == PanelGeometry.minSize)
        #expect(PanelGeometry.clamp(NSSize(width: -100, height: -50)) == PanelGeometry.minSize)
    }

    @Test("非有限值退回默认尺寸，不炸")
    func clampNonFinite() {
        #expect(PanelGeometry.clamp(NSSize(width: CGFloat.nan, height: 400)) == PanelGeometry.defaultSize)
        #expect(PanelGeometry.clamp(NSSize(width: 400, height: CGFloat.infinity)) == PanelGeometry.defaultSize)
    }

    @Test("折叠态那个 40×40 不会被 minSize 抬成 280×180")
    func frameKeepsCollapsedSize() {
        // 定死的尺寸（折叠浮标）不走用户尺寸的下限。抬成 280×180 的话，点折叠按钮会先缩成
        // 中等大小、再由宿主视图缩成小浮标，屏幕上就是「先缩小、再收起」
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 860)
        let collapsed = NSSize(width: 40, height: 40)
        let rect = PanelGeometry.frame(anchoringTopLeft: NSPoint(x: 100, y: 700),
                                       size: collapsed, inVisible: visible)
        #expect(rect.size == collapsed)
        #expect(rect.origin == NSPoint(x: 100, y: 660), "左上角锚点不动")
    }

    @Test("frame：空间够时尺寸位置原样，左上角锚点不动")
    func frameNormal() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = PanelGeometry.frame(anchoringTopLeft: NSPoint(x: 100, y: 700),
                                       size: NSSize(width: 400, height: 500),
                                       inVisible: visible)
        #expect(rect.size == NSSize(width: 400, height: 500))
        #expect(rect.origin == NSPoint(x: 100, y: 200))
    }

    @Test("frame：贴屏幕右边拖大时窗口向左让，仍然整个可见")
    func frameSlidesLeftAtRightEdge() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = PanelGeometry.frame(anchoringTopLeft: NSPoint(x: 900, y: 700),
                                       size: NSSize(width: 400, height: 500),
                                       inVisible: visible)
        #expect(rect.maxX == visible.maxX)
        #expect(rect.minX == 600)
    }

    @Test("frame：锚点离屏边只剩一点空间时不会硬撑到 minSize 出屏")
    func frameNearEdgeKeepsInside() {
        // 锚点距右边缘只剩 100pt。旧实现把「可用空间」的下限兜成 minSize(280)，
        // 于是这个尺寸会被抬到 280，窗口必然出屏、松手又被拉回来——就是那个「跳一下」
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = PanelGeometry.frame(anchoringTopLeft: NSPoint(x: 900, y: 700),
                                       size: NSSize(width: 300, height: 200),
                                       inVisible: visible)
        #expect(rect.size == NSSize(width: 300, height: 200))
        #expect(rect.maxX == visible.maxX)
    }

    @Test("frame：尺寸超过屏幕时按屏幕钳，整帧留在屏幕内")
    func frameClampsToScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = PanelGeometry.frame(anchoringTopLeft: NSPoint(x: 100, y: 700),
                                       size: NSSize(width: 900, height: 900),
                                       inVisible: visible)
        #expect(rect.size == NSSize(width: 900, height: 800))
        #expect(visible.contains(rect))
    }

    @Test("frame：锚点已在屏幕外（窗口被拖出去过）也拉回屏幕内")
    func framePullsOffscreenAnchorBack() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = PanelGeometry.frame(anchoringTopLeft: NSPoint(x: 1200, y: 900),
                                       size: NSSize(width: 400, height: 500),
                                       inVisible: visible)
        #expect(rect.maxX == visible.maxX)
        #expect(rect.maxY == visible.maxY)
    }

    @Test("拖拽时手柄始终跟着鼠标；拖出屏幕的部分被贴回屏幕边")
    func handleFollowsCursor() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 860)
        let startFrame = NSRect(x: 400, y: 300, width: 360, height: 440)
        let startMouse = NSPoint(x: startFrame.maxX, y: startFrame.minY)  // 手柄在右下角
        let startAnchor = NSPoint(x: startFrame.minX, y: startFrame.maxY)

        // 屏幕中间往右下拖：手柄就落在鼠标处
        let inside = NSPoint(x: startMouse.x + 120, y: startMouse.y - 90)
        let size = PanelGeometry.resized(start: startFrame.size, startMouse: startMouse, currentMouse: inside)
        let rect = PanelGeometry.frame(anchoringTopLeft: startAnchor, size: size, inVisible: visible)
        #expect(rect.maxX == inside.x)
        #expect(rect.minY == inside.y)

        // 往右下拖到屏幕外：窗口整个被贴回屏幕内
        // （宽度会先被 maxSize 封顶，所以右边不一定顶到屏幕边；底边是贴住的）
        let outside = NSPoint(x: visible.maxX + 300, y: visible.minY - 300)
        let bigSize = PanelGeometry.resized(start: startFrame.size, startMouse: startMouse, currentMouse: outside)
        let clamped = PanelGeometry.frame(anchoringTopLeft: startAnchor, size: bigSize, inVisible: visible)
        #expect(clamped.minY == visible.minY)
        #expect(visible.contains(clamped))
    }

    @Test("拖拽期间的 frame 与松手提交算出的 frame 完全一致（不会跳一下）")
    func dragFrameMatchesCommitFrame() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 860)
        // 覆盖贴左上/右上/左下/右下/屏幕外的各种起点
        let starts = [
            NSRect(x: 24, y: 24, width: 360, height: 440),
            NSRect(x: 600, y: 300, width: 360, height: 440),
            NSRect(x: 1056, y: 396, width: 360, height: 440),   // 默认的右上角位置
            NSRect(x: 1400, y: 24, width: 360, height: 440),    // 贴右边
            NSRect(x: 24, y: -100, width: 360, height: 440),    // 有一部分在屏幕外
        ]
        let deltas = [NSPoint(x: 0, y: 0), NSPoint(x: 200, y: -300), NSPoint(x: -250, y: 120),
                      NSPoint(x: 600, y: -600), NSPoint(x: -900, y: 900)]

        for startFrame in starts {
            for delta in deltas {
                let startMouse = NSPoint(x: startFrame.maxX, y: startFrame.minY)
                let currentMouse = NSPoint(x: startMouse.x + delta.x, y: startMouse.y + delta.y)
                let size = PanelGeometry.resized(start: startFrame.size,
                                                 startMouse: startMouse,
                                                 currentMouse: currentMouse)
                // 拖拽期间：锚点取一次，全程从起点重算
                let during = PanelGeometry.frame(anchoringTopLeft: NSPoint(x: startFrame.minX, y: startFrame.maxY),
                                                 size: size, inVisible: visible)
                // 松手提交：AppDelegate 以「窗口现在的左上角」为锚点再算一次
                let after = PanelGeometry.frame(anchoringTopLeft: NSPoint(x: during.minX, y: during.maxY),
                                                size: size, inVisible: visible)
                #expect(during == after,
                        "起点 \(startFrame) 位移 \(delta)：拖拽帧 \(during) 与提交帧 \(after) 不一致")
            }
        }
    }

    @Test("往右下拖两个方向都变大，往左上拖都变小")
    func resizeDirections() {
        let start = NSSize(width: 400, height: 500)
        let origin = NSPoint(x: 100, y: 100)

        // 屏幕坐标 y 轴向上：往**下**拖是 y 变小
        let bigger = PanelGeometry.resized(start: start, startMouse: origin,
                                           currentMouse: NSPoint(x: 150, y: 60))
        #expect(bigger == NSSize(width: 450, height: 540))

        let smaller = PanelGeometry.resized(start: start, startMouse: origin,
                                            currentMouse: NSPoint(x: 60, y: 150))
        #expect(smaller == NSSize(width: 360, height: 450))
    }

    @Test("拖到上下限就停住")
    func resizeClampsAtBounds() {
        let origin = NSPoint(x: 0, y: 0)

        let tiny = PanelGeometry.resized(start: NSSize(width: 400, height: 500), startMouse: origin,
                                         currentMouse: NSPoint(x: -900, y: 900))
        #expect(tiny == PanelGeometry.minSize)

        let huge = PanelGeometry.resized(start: NSSize(width: 400, height: 500), startMouse: origin,
                                         currentMouse: NSPoint(x: 5000, y: -5000))
        #expect(huge == PanelGeometry.maxSize)
    }
}

@Suite("悬浮窗尺寸（AppState）")
final class FloatingPanelSizeTests {
    private let storageURL: URL
    private let state: AppState

    init() {
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("attention-panel-tests-\(UUID().uuidString).json")
        state = AppState(storageURL: storageURL, autoEndEnabled: true, startTimers: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: storageURL)
    }

    @Test("默认尺寸与菜单栏面板一致")
    func defaultSize() {
        #expect(state.floatingPanelSize == PanelGeometry.defaultSize)
    }

    @Test("注入越界尺寸会被钳回合法区间")
    func injectedSizeIsClamped() {
        let injected = AppState(storageURL: storageURL,
                                autoEndEnabled: true,
                                startTimers: false,
                                floatingPanelSize: NSSize(width: 10, height: 99_999))

        #expect(injected.floatingPanelSize == NSSize(width: PanelGeometry.minSize.width,
                                                     height: PanelGeometry.maxSize.height))
    }

    @Test("resizeFloatingPanel 写入的是钳制后的值")
    func resizeClamps() {
        state.resizeFloatingPanel(to: NSSize(width: 9999, height: 9999))
        #expect(state.floatingPanelSize == PanelGeometry.maxSize)

        state.resizeFloatingPanel(to: NSSize(width: 420, height: 520))
        #expect(state.floatingPanelSize == NSSize(width: 420, height: 520))
    }

    @Test("@Published 在 willSet 里投递，订阅回调里回读属性拿到的是旧值")
    func publishedDeliversBeforePropertyIsWritten() {
        // 悬浮窗窗口尺寸就是靠这个订阅驱动的：必须用**投递过来的值**，不能在回调里回读
        // `floatingPanelSize`——那会拿到改之前的尺寸，表现为「松手后窗口被打回上一次的大小」。
        // 这条用例把这个前提钉住，免得有人把回读的写法又写回来。
        var emitted: NSSize?
        var readBack: NSSize?
        let cancellable = state.$floatingPanelSize
            .sink { [state] value in
                emitted = value
                readBack = state.floatingPanelSize
            }

        state.resizeFloatingPanel(to: NSSize(width: 420, height: 520))

        #expect(emitted == NSSize(width: 420, height: 520))
        #expect(readBack == NSSize(width: 360, height: 440), "willSet 投递时属性还没写入")
        cancellable.cancel()
    }

    @Test("折叠再展开不丢用户尺寸")
    func collapseKeepsSize() {
        state.resizeFloatingPanel(to: NSSize(width: 300, height: 260))

        state.isPanelCollapsed = true
        state.isPanelCollapsed = false

        #expect(state.floatingPanelSize == NSSize(width: 300, height: 260),
                "折叠态是固定的小浮标，不该把用户调好的尺寸冲掉")
    }
}
