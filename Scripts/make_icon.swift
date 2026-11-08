// 生成应用图标（作者选定方案）：半透磨砂浅色底板铺满整个画布 + 2×2 真实 App 图标
// 图案铺满画布（不留透明边）—— macOS 26+ 会对"有透明边的旧式图标"自动套玻璃容器，
// 那就是之前"嵌套方块"的元凶；铺满后系统只负责切圆角，不再套壳。
// 图标来源：读取真实名单（~/Library/Application Support/DockDrawer/config.json），
// 按顺序取前 4 个真实存在的 App；不足的格子用灰块占位。
// 用法：在 dock-drawer 目录下执行  swift Scripts/make_icon.swift
import AppKit

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// 1. 磨砂观感的浅灰白底板（必须完全不透明 alpha=1.0 —— 半透明会触发系统玻璃垫板，
//    垫板灰色从半透底透出来 = 灰边缘/嵌套观感的最终病根）
let bg = NSGradient(colors: [NSColor(calibratedWhite: 0.76, alpha: 1.0),
                             NSColor(calibratedWhite: 0.50, alpha: 1.0)])!
bg.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas), angle: -90)
// 高光描边（提亮边缘）
NSColor.white.withAlphaComponent(0.9).setStroke()
let border = NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: canvas - 8, height: canvas - 8),
                          xRadius: 238, yRadius: 238)
border.lineWidth = 6
border.stroke()

// 2. 从真实名单取前 4 个存在的 App
let configPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/DockDrawer/config.json")
var picked: [String] = []
if let data = try? Data(contentsOf: configPath),
   let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
    for entry in raw {
        if let folder = entry["folder"] as? [String: Any],
           let apps = folder["apps"] as? [[String: Any]] {
            for app in apps {
                if let path = app["path"] as? String { picked.append(path) }
            }
        }
        if let app = entry["app"] as? [String: Any],
           let path = app["path"] as? String { picked.append(path) }
    }
}
let fm = FileManager.default
let realApps = picked.filter { fm.fileExists(atPath: $0) }.prefix(4)
print("picked apps: \(realApps)")

// 3. 2×2 真实图标网格（格子 320，间距 20，边距 82）
let tile: CGFloat = 360
let gap: CGFloat = 18
let margin = (canvas - 2 * tile - gap) / 2
let iconShadow = NSShadow()
iconShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
iconShadow.shadowBlurRadius = 14
iconShadow.shadowOffset = NSSize(width: 0, height: -6)
for index in 0..<4 {
    let row = index / 2
    let col = index % 2
    let x = margin + CGFloat(col) * (tile + gap)
    let y = canvas - margin - tile - CGFloat(row) * (tile + gap)
    let rect = NSRect(x: x, y: y, width: tile, height: tile)
    NSGraphicsContext.current?.saveGraphicsState()
    iconShadow.set()
    if index < realApps.count {
        let icon = NSWorkspace.shared.icon(forFile: realApps[index])
        icon.size = rect.size
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        // 空位：低调灰块
        NSColor.black.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 24, dy: 24),
                     xRadius: 60, yRadius: 60).fill()
    }
    NSGraphicsContext.current?.restoreGraphicsState()
}

image.unlockFocus()

// 多尺寸 iconset → icns
let outDir = URL(fileURLWithPath: "Resources/AppIcon.iconset", isDirectory: true)
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
print("icons written to \(outDir.path)")
