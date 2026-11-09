// 生成「公开分发版」应用图标：纯原创抽象几何，不读取本机名单、不含任何第三方 App 图标。
// 遵守 AGENTS.md R2：画布必须 alpha=1.0 完全不透明（深灰渐变底板铺满），否则 macOS 26+
// 会垫一层玻璃底板，出现灰边/嵌套方块。视觉语言沿用定稿（0.76→0.50 渐变 + 白色高光描边 +
// 2×2 磁贴布局），只把「真实 App 图标」换成四个抽象符号，可安全随公开仓库/安装包分发。
//
// 用法：在项目根目录执行  swift Scripts/make_release_icon.swift
// 产物：Resources/Release/AppIcon.iconset/ + Resources/Release/AppIcon.icns
import AppKit
import Foundation

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// 1. 不透明深灰渐变底板（铺满整个画布，alpha = 1.0）
let bg = NSGradient(colors: [NSColor(calibratedWhite: 0.76, alpha: 1.0),
                             NSColor(calibratedWhite: 0.50, alpha: 1.0)])!
bg.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas), angle: -90)

// 高光描边（提亮边缘，与本地定稿一致）
NSColor.white.withAlphaComponent(0.9).setStroke()
let border = NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: canvas - 8, height: canvas - 8),
                          xRadius: 238, yRadius: 238)
border.lineWidth = 6
border.stroke()

// 2. 2×2 磁贴：尺寸与定稿一致（tile 360 / gap 18），内容改为原创抽象符号
let tile: CGFloat = 360
let gap: CGFloat = 18
let margin = (canvas - 2 * tile - gap) / 2
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
shadow.shadowBlurRadius = 14
shadow.shadowOffset = NSSize(width: 0, height: -6)

// 四个柔和色仅作装饰，均为通用配色，不对应任何具体产品标识
let palette: [NSColor] = [
    NSColor(calibratedRed: 0.36, green: 0.56, blue: 0.98, alpha: 1.0), // 蓝
    NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.65, alpha: 1.0), // 绿
    NSColor(calibratedRed: 0.96, green: 0.74, blue: 0.09, alpha: 1.0), // 橙
    NSColor(calibratedRed: 0.57, green: 0.44, blue: 0.79, alpha: 1.0)  // 紫
]

func tileRect(_ index: Int) -> NSRect {
    let row = index / 2
    let col = index % 2
    let x = margin + CGFloat(col) * (tile + gap)
    let y = canvas - margin - tile - CGFloat(row) * (tile + gap)
    return NSRect(x: x, y: y, width: tile, height: tile)
}

func stroke(_ path: NSBezierPath, width: CGFloat) {
    NSColor.white.setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

for index in 0..<4 {
    let rect = tileRect(index)
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()

    // 磁贴本体：不透明圆角方块
    let plate = NSBezierPath(roundedRect: rect, xRadius: 80, yRadius: 80)
    palette[index].setFill()
    plate.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // 白色抽象符号（纯几何，无品牌含义）
    let s = tile / 360
    let cx = rect.midX
    let cy = rect.midY
    switch index {
    case 0:
        // 文件夹：描边主体 + 左上角实心标签（盖住顶边左段，形成标准文件夹轮廓）
        let body = NSBezierPath(roundedRect: NSRect(x: cx - 110*s, y: cy - 76*s,
                                                   width: 220*s, height: 140*s),
                               xRadius: 22*s, yRadius: 22*s)
        stroke(body, width: 18*s)
        let tab = NSBezierPath(roundedRect: NSRect(x: cx - 110*s, y: cy + 48*s,
                                                   width: 104*s, height: 32*s),
                               xRadius: 14*s, yRadius: 14*s)
        NSColor.white.setFill()
        tab.fill()
    case 1:
        // 2×2 点阵：代表网格里的 App
        for dx in [-1, 1] {
            for dy in [-1, 1] {
                let p = NSBezierPath(ovalIn: NSRect(x: cx + CGFloat(dx)*52*s - 30*s,
                                                    y: cy + CGFloat(dy)*52*s - 30*s,
                                                    width: 60*s, height: 60*s))
                NSColor.white.setFill()
                p.fill()
            }
        }
    case 2:
        // 三横线：代表列表 / 收纳
        for dy in [-1, 0, 1] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: cx - 100*s, y: cy + CGFloat(dy)*56*s))
            line.line(to: NSPoint(x: cx + 100*s, y: cy + CGFloat(dy)*56*s))
            stroke(line, width: 20*s)
        }
    default:
        // 抽屉：外框 + 中间拉手
        let outer = NSBezierPath(roundedRect: NSRect(x: cx - 112*s, y: cy - 96*s,
                                                    width: 224*s, height: 176*s),
                                xRadius: 24*s, yRadius: 24*s)
        stroke(outer, width: 18*s)
        let handle = NSBezierPath(roundedRect: NSRect(x: cx - 54*s, y: cy - 14*s,
                                                     width: 108*s, height: 28*s),
                                 xRadius: 14*s, yRadius: 14*s)
        NSColor.white.setFill()
        handle.fill()
    }
}

image.unlockFocus()

// 3. 多尺寸 iconset → icns（与本地定稿同一套 10 个尺寸）
let outDir = URL(fileURLWithPath: "Resources/Release/AppIcon.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
if let old = try? FileManager.default.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil) {
    for file in old { try? FileManager.default.removeItem(at: file) }
}
let plan: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]
for entry in plan {
    let scaled = NSImage(size: NSSize(width: entry.0, height: entry.0))
    scaled.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: entry.0, height: entry.0),
               from: .zero, operation: .copy, fraction: 1)
    scaled.unlockFocus()
    guard let tiff = scaled.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: outDir.appendingPathComponent(entry.1))
}

let icnsURL = URL(fileURLWithPath: "Resources/Release/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", outDir.path, "-o", icnsURL.path]
try? task.run()
task.waitUntilExit()
print("public icon written to \(icnsURL.path) (iconutil exit: \(task.terminationStatus))")
