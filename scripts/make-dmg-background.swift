#!/usr/bin/env swift
//
//  生成 dmg 安装界面的背景图。
//
//  用法：
//    swift scripts/make-dmg-background.swift /tmp/dmg-bg
//    产出 dmg-background.png（600×400）与 dmg-background@2x.png（1200×800）
//
//  背景只画一个从「应用图标位」指向「应用程序快捷方式位」的箭头。
//  两端的图标坐标由 scripts/make-dmg.sh 里的 AppleScript 设置，改这里要同步改那边。
//

import Foundation
import CoreGraphics
import ImageIO

// 与 make-dmg.sh 中窗口内容区尺寸保持一致
let DESIGN_W: CGFloat = 600
let DESIGN_H: CGFloat = 400

let BG = (r: 0.969, g: 0.969, b: 0.976)     // #F7F7F9 浅灰底
let ARROW = (r: 0.780, g: 0.780, b: 0.800)  // #C7C7CC 箭头

/// 图标中心位置，坐标系原点在内容区左上角、y 向下（和 Finder 一致）
let LEFT_X: CGFloat = 150
let RIGHT_X: CGFloat = 450
let ICON_Y: CGFloat = 190

func rgb(_ c: (r: Double, g: Double, b: Double)) -> CGColor {
    CGColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
}

func makeBackground(scale: CGFloat) -> CGImage? {
    let w = Int(DESIGN_W * scale)
    let h = Int(DESIGN_H * scale)
    let u = scale

    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.setShouldAntialias(true)

    // 底色
    ctx.setFillColor(rgb(BG))
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))

    // CG 的 y 轴向上，Finder 的 y 轴向下，这里换算一次
    let y = (DESIGN_H - ICON_Y) * u

    // 箭头杆：两端各留出一段空隙，避免贴着图标
    ctx.setStrokeColor(rgb(ARROW))
    ctx.setLineWidth(6 * u)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: (LEFT_X + 95) * u, y: y))
    ctx.addLine(to: CGPoint(x: (RIGHT_X - 105) * u, y: y))
    ctx.strokePath()

    // 箭头头部
    ctx.setFillColor(rgb(ARROW))
    ctx.move(to: CGPoint(x: (RIGHT_X - 78) * u, y: y))
    ctx.addLine(to: CGPoint(x: (RIGHT_X - 108) * u, y: y + 15 * u))
    ctx.addLine(to: CGPoint(x: (RIGHT_X - 108) * u, y: y - 15 * u))
    ctx.closePath()
    ctx.fillPath()

    return ctx.makeImage()
}

// MARK: - 输出

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                 ? CommandLine.arguments[1]
                 : ".")

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("错误：\(msg)\n".data(using: .utf8)!)
    exit(1)
}

do {
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
} catch {
    fail("无法创建输出目录 \(outDir.path)：\(error)")
}

let specs: [(String, CGFloat)] = [
    ("dmg-background.png", 1),
    ("dmg-background@2x.png", 2),
]

for (name, scale) in specs {
    guard let img = makeBackground(scale: scale) else { fail("绘制 \(name) 失败") }
    let url = outDir.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("无法写入 \(url.path)")
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fail("写出 \(name) 失败") }
}

print("✅ 已生成背景图 → \(outDir.path)")
