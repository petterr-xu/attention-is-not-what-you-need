#!/usr/bin/env swift
//
//  生成 Attention 应用图标。
//
//  用法：
//    swift scripts/make-icon.swift /tmp/AppIcon.iconset
//    iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
//
//  设计：圆角方形底 + 靛蓝→紫渐变，中间三条清单行。
//        第一行亮青绿（当前任务，对应应用里「当前任务置顶高亮」的核心交互），
//        其余两行半透明白（挂起任务），左侧空心圆点表示未完成。
//

import Foundation
import CoreGraphics
import ImageIO

// MARK: - 设计基准（均以 1024×1024 画布为单位）

let DESIGN: CGFloat = 1024
let CONTENT_INSET: CGFloat = 100      // 四周留白，遵循 macOS Big Sur 图标规范
let CORNER_RADIUS: CGFloat = 185.4    // 内容圆角 ≈ 内容边长的 22.5%

let BG_TOP = (r: 0.298, g: 0.357, b: 0.831)     // #4C5BD4 靛蓝
let BG_BOTTOM = (r: 0.478, g: 0.294, b: 0.776)  // #7A4BC6 紫
let ACCENT = (r: 0.431, g: 0.910, b: 0.784)     // #6EE8C8 亮青绿
let WHITE = (r: 1.0, g: 1.0, b: 1.0)

let DOT_D: CGFloat = 72               // 圆点直径
let DOT_GAP: CGFloat = 44             // 圆点与横条的间距
let BAR_W: CGFloat = 400              // 横条宽度
let BAR_H: CGFloat = 72               // 横条高度
let ROW_GAP: CGFloat = 64             // 行间距

// MARK: - 绘制

func rgb(_ c: (r: Double, g: Double, b: Double), _ a: Double) -> CGColor {
    CGColor(red: c.r, green: c.g, blue: c.b, alpha: a)
}

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func makeIcon(px: Int) -> CGImage? {
    let S = CGFloat(px)
    let u = S / DESIGN                        // 设计单位 → 像素

    guard let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // ---- 背景：圆角矩形 + 垂直渐变 ----
    let inset = CONTENT_INSET * u
    let bgRect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    ctx.saveGState()
    ctx.addPath(roundedPath(bgRect, CORNER_RADIUS * u))
    ctx.clip()
    if let grad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [rgb(BG_TOP, 1), rgb(BG_BOTTOM, 1)] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: bgRect.midX, y: bgRect.maxY),
            end: CGPoint(x: bgRect.midX, y: bgRect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // ---- 清单三条 ----
    // 所有几何尺寸都必须从设计单位换算到像素，否则小尺寸下会画到画布外
    let dotD = DOT_D * u
    let dotGap = DOT_GAP * u
    let barH = BAR_H * u
    let rowGap = ROW_GAP * u
    let barWFull = BAR_W * u

    // 16/32px 下圆点会糊成一团，省略圆点、让横条占满整行
    let drawDot = px > 32

    let totalW = dotD + dotGap + barWFull
    let originX = (S - totalW) / 2
    let rowStep = barH + rowGap
    let midY = S / 2

    let barX = drawDot ? originX + dotD + dotGap : originX
    let barW = drawDot ? barWFull : totalW

    for i in 0..<3 {
        let centerY = midY + (1 - CGFloat(i)) * rowStep
        let isCurrent = (i == 0)

        // 横条
        ctx.addPath(roundedPath(
            CGRect(x: barX, y: centerY - barH / 2, width: barW, height: barH),
            barH / 2
        ))
        ctx.setFillColor(isCurrent ? rgb(ACCENT, 1) : rgb(WHITE, 0.30))
        ctx.fillPath()

        guard drawDot else { continue }

        // 左侧圆点：当前任务实心，其余空心
        let dotRect = CGRect(x: originX, y: centerY - dotD / 2, width: dotD, height: dotD)
        if isCurrent {
            ctx.addPath(CGPath(ellipseIn: dotRect, transform: nil))
            ctx.setFillColor(rgb(ACCENT, 1))
            ctx.fillPath()
        } else {
            let lw = 11 * u
            ctx.addPath(CGPath(ellipseIn: dotRect.insetBy(dx: lw / 2, dy: lw / 2), transform: nil))
            ctx.setStrokeColor(rgb(WHITE, 0.45))
            ctx.setLineWidth(lw)
            ctx.strokePath()
        }
    }

    return ctx.makeImage()
}

// MARK: - 输出 iconset

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                 ? CommandLine.arguments[1]
                 : "AppIcon.iconset")

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("错误：\(msg)\n".data(using: .utf8)!)
    exit(1)
}

do {
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
} catch {
    fail("无法创建输出目录 \(outDir.path)：\(error)")
}

for (name, px) in specs {
    guard let img = makeIcon(px: px) else { fail("绘制 \(name) 失败") }
    let url = outDir.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("无法写入 \(url.path)")
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fail("写出 \(name) 失败") }
}

print("✅ 已生成 \(specs.count) 个尺寸 → \(outDir.path)")
