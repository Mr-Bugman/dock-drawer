import AppKit
import SwiftUI

/// 调试用：在桌面中央并排摆出几种玻璃质感的小面板，供真人对比挑选。
/// 启动方式：DOCKDRAWER_GLASS_PREVIEW=1 运行 App。
enum GlassPreview {
    struct Variant {
        let title: String
        let style: NSGlassEffectView.Style
        let frost: CGFloat
    }

    static let variants: [Variant] = [
        Variant(title: "A · 全透（最透）", style: .clear, frost: 0),
        Variant(title: "B · 全透 + 25% 雾", style: .clear, frost: 0.25),
        Variant(title: "C · 全透 + 50% 雾", style: .clear, frost: 0.50),
        Variant(title: "D · 标准玻璃（最雾）", style: .regular, frost: 0)
    ]

    private static var panels: [NSPanel] = []

    static func show() {
        let size = NSSize(width: 250, height: 180)
        let gap: CGFloat = 18
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let totalWidth = CGFloat(variants.count) * size.width + CGFloat(variants.count - 1) * gap
        var x = screen.midX - totalWidth / 2
        let y = screen.midY - size.height / 2

        for variant in variants {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.cornerRadius = 18
            glass.style = variant.style
            let hosting = NSHostingView(rootView: PreviewTileView(variant: variant))
            hosting.frame = NSRect(origin: .zero, size: size)
            glass.contentView = hosting
            panel.contentView = glass
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            panel.orderFront(nil)
            panels.append(panel)
            x += size.width + gap
        }
        NSLog("DockDrawer glass preview: \(variants.count) panels shown")
    }
}

struct PreviewTileView: View {
    let variant: GlassPreview.Variant

    var body: some View {
        ZStack {
            if variant.frost > 0 {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(variant.frost))
            }
            VStack(spacing: 12) {
                Text(variant.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                HStack(spacing: 10) {
                    tile(imageName: "calculator.fill", color: .orange)
                    tile(imageName: "note.text", color: .yellow)
                    tile(imageName: "music.note", color: .pink)
                    tile(imageName: "map.fill", color: .green)
                }
                Text("黑字白字对比：透到什么程度刚刚好？")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Text("这行灰字能不能看清也很重要")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tile(imageName: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(color.opacity(0.85))
            Image(systemName: imageName)
                .font(.system(size: 16))
                .foregroundColor(.white)
        }
        .frame(width: 36, height: 36)
    }
}

// MARK: - 气泡样式预览（DOCKDRAWER_BUBBLE_PREVIEW=1）
//
// 整个气泡轮廓（面板 + 尾巴）用一条路径画出来，五个档位并排比形状。
// 形状选定后再用玻璃实现（预览里用半透白近似，五档画法一致，方便公平对比）。

enum BubblePreview {
    struct Spec {
        let title: String
        let style: Style
        enum Style { case dockSharp; case dockCurved; case dockSmall; case plain }
    }

    static let specs: [Spec] = [
        Spec(title: "A · Dock 原生尖角", style: .dockSharp),
        Spec(title: "B · 内弯弧边尖角", style: .dockCurved),
        Spec(title: "C · 短小尖角", style: .dockSmall),
        Spec(title: "D · 现状（无尾巴）", style: .plain)
    ]
}

// MARK: - 气泡形状（SwiftUI Shape 版，可离线渲染成图片）
//
// y 向下坐标系：主体在上，尾巴区域在下（tailExtra 高）。

struct BubbleSilhouetteShape: Shape {
    let style: BubblePreview.Spec.Style
    static let tailExtra: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let bodyRect = CGRect(x: 0, y: 0, width: rect.width, height: rect.height - Self.tailExtra)
        let midX = rect.midX
        let bodyBottom = bodyRect.maxY
        let corner = CGSize(width: 20, height: 20)
        p.addRoundedRect(in: bodyRect, cornerSize: corner)

        switch style {
        case .dockSharp:
            // Dock 悬浮名称气泡那种小尖角：直边小三角
            p.move(to: CGPoint(x: midX - 8, y: bodyBottom))
            p.addLine(to: CGPoint(x: midX, y: bodyBottom + 12))
            p.addLine(to: CGPoint(x: midX + 8, y: bodyBottom))
            p.closeSubpath()
        case .dockCurved:
            // 内弯弧边：两侧微微向内收，更柔
            p.move(to: CGPoint(x: midX - 8, y: bodyBottom))
            p.addQuadCurve(to: CGPoint(x: midX, y: bodyBottom + 13),
                           control: CGPoint(x: midX - 2, y: bodyBottom + 9))
            p.addQuadCurve(to: CGPoint(x: midX + 8, y: bodyBottom),
                           control: CGPoint(x: midX + 2, y: bodyBottom + 9))
            p.closeSubpath()
        case .dockSmall:
            // 更短更小的尖角
            p.move(to: CGPoint(x: midX - 6, y: bodyBottom))
            p.addLine(to: CGPoint(x: midX, y: bodyBottom + 9))
            p.addLine(to: CGPoint(x: midX + 6, y: bodyBottom))
            p.closeSubpath()
        case .plain:
            break
        }
        return p
    }
}

enum BubblePreviewRenderer {
    /// 把五个气泡形状渲染成 PNG（不依赖窗口，直接 ImageRenderer 出图）
    @MainActor
    static func renderAllToDisk(dir: String) {
        for (index, spec) in BubblePreview.specs.enumerated() {
            let filled = BubbleSilhouetteShape(style: spec.style)
                .fill(Color.white.opacity(0.92))
            let outline = BubbleSilhouetteShape(style: spec.style)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
            let content = ZStack {
                filled
                outline
                BubblePreviewContent(spec: spec)
            }
            .frame(width: 260, height: 146)
            .background(Color(NSColor.windowBackgroundColor))

            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let nsImage = renderer.nsImage,
               let tiff = nsImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/bubble_\(index).png"))
            }
        }
    }
}

struct BubblePreviewContent: View {
    let spec: BubblePreview.Spec

    var body: some View {
        VStack(spacing: 8) {
            Text(spec.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
            HStack(spacing: 10) {
                icon(index: 0)
                icon(index: 1)
                icon(index: 2)
                icon(index: 3)
            }
            Text("形状选定后用玻璃实现")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
    }

    private func icon(index i: Int) -> some View {
        let colors: [Color] = [.orange, .yellow, .pink, .green]
        let names = ["calculator.fill", "note.text", "music.note", "map.fill"]
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(colors[i].opacity(0.85))
            Image(systemName: names[i])
                .font(.system(size: 15))
                .foregroundColor(.white)
        }
        .frame(width: 40, height: 40)
    }
}

// MARK: - 应用图标候选预览（DOCKDRAWER_ICON_PREVIEW=1）
//
// 每个候选都是 512×512 的 SwiftUI 绘制，ImageRenderer 出 PNG 给作者挑选。

enum IconPreviewRenderer {
    @MainActor
    static func renderAllToDisk(dir: String) {
        let current = NSImage(contentsOf: Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/AppIcon.icns"))
        let candidates: [(String, AnyView)] = [
            ("A", AnyView(IconCandidate.drawerChest)),
            ("B", AnyView(IconCandidate.minimalLine)),
            ("C", AnyView(IconCandidate.trayArrow)),
            ("D", AnyView(IconCandidate.glowDrawer)),
            ("E", AnyView(IconCandidate.current(current)))
        ]
        for (name, view) in candidates {
            let renderer = ImageRenderer(content: view.frame(width: 512, height: 512))
            renderer.scale = 1
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
            }
        }
    }
}

enum IconCandidate {
    // A · 拉开的抽屉柜：深色柜体 + 浅色抽屉滑出 + 把手，强调"抽屉"而不是"文件夹"
    static var drawerChest: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 115)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.24, blue: 0.48),
                                              Color(red: 0.07, green: 0.11, blue: 0.26)],
                                     startPoint: .top, endPoint: .bottom))
            // 柜体
            RoundedRectangle(cornerRadius: 56)
                .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.14, blue: 0.32),
                                              Color(red: 0.05, green: 0.08, blue: 0.20)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 330, height: 220)
                .offset(y: 55)
            // 抽屉口（深色开口）+ 透出的光
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black.opacity(0.6))
                .frame(width: 276, height: 64)
                .offset(y: -18)
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color.yellow.opacity(0.75), Color.orange.opacity(0.35)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 252, height: 44)
                .offset(y: -22)
            // 拉出来的抽屉
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: [Color.white, Color(white: 0.82)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 300, height: 118)
                .overlay(
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.72, blue: 0.25),
                                                      Color(red: 0.85, green: 0.52, blue: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 96, height: 18)
                        .offset(y: -22)
                )
                .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
                .offset(y: 62)
        }
    }

    // B · 极简线条：浅底 + 单色描线抽屉
    static var minimalLine: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 115)
                .fill(LinearGradient(colors: [Color(white: 0.99), Color(white: 0.92)],
                                     startPoint: .top, endPoint: .bottom))
            let stroke = Color(red: 0.15, green: 0.42, blue: 0.95)
            Group {
                RoundedRectangle(cornerRadius: 42)
                    .stroke(stroke, lineWidth: 16)
                    .frame(width: 260, height: 220)
                    .offset(y: 30)
                RoundedRectangle(cornerRadius: 26)
                    .stroke(stroke, lineWidth: 13)
                    .frame(width: 180, height: 110)
                    .offset(y: 52)
                Capsule()
                    .fill(stroke)
                    .frame(width: 76, height: 16)
                    .offset(y: 52)
                Rectangle()
                    .fill(stroke)
                    .frame(width: 180, height: 4)
                    .offset(y: -28)
            }
            HStack(spacing: 22) {
                Circle().fill(stroke).frame(width: 18, height: 18)
                Circle().fill(stroke.opacity(0.65)).frame(width: 18, height: 18)
                Circle().fill(stroke.opacity(0.4)).frame(width: 18, height: 18)
            }
            .offset(y: -60)
        }
    }

    // C · 托盘上箭头："取出到桌面"的隐喻
    static var trayArrow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 115)
                .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.44, blue: 0.92),
                                              Color(red: 0.05, green: 0.25, blue: 0.60)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 150, weight: .bold))
                    .foregroundColor(.white)
                    .offset(y: -12)
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 34)
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 270, height: 96)
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color(red: 0.07, green: 0.30, blue: 0.68))
                        .frame(width: 222, height: 26)
                        .offset(y: -14)
                }
            }
            .offset(y: 66)
        }
    }

    // D · 深色宝箱：抽屉里透出光和小 App 方块，"藏宝抽屉"
    static var glowDrawer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 115)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
            RadialGradient(colors: [Color.yellow.opacity(0.95), Color.orange.opacity(0.5), Color.clear],
                           center: .center, startRadius: 10, endRadius: 190)
                .frame(width: 380, height: 260)
                .offset(y: -10)
            HStack(spacing: 14) {
                appTile(Color(red: 0.35, green: 0.72, blue: 0.98), rotation: -8)
                appTile(Color(red: 0.98, green: 0.80, blue: 0.30), rotation: 5)
                appTile(Color(red: 0.45, green: 0.85, blue: 0.55), rotation: 10)
            }
            .offset(y: -52)
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.14)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 310, height: 132)
                .overlay(
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.32),
                                                      Color(red: 0.88, green: 0.58, blue: 0.15)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 88, height: 16)
                )
                .overlay(RoundedRectangle(cornerRadius: 30)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 2))
                .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
                .offset(y: 74)
        }
    }

    private static func appTile(_ color: Color, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(LinearGradient(colors: [color, color.opacity(0.75)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 62, height: 62)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 3))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 4)
            .rotationEffect(.degrees(rotation))
    }

    // E · 现状对照（当前图标）
    static func current(_ image: NSImage?) -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: 115).fill(Color.gray)
            }
        }
        .frame(width: 512, height: 512)
    }
}

// MARK: - 文件夹磁贴风图标（DOCKDRAWER_ICON_PREVIEW=1 时一并渲染）
//
// 作者想要的：软件里二级文件夹磁贴的样子——浅色圆角方块 + 3×3 彩色小 App 图标网格。

enum IconTileRenderer {
    @MainActor
    static func renderAllToDisk(dir: String) {
        let candidates: [(String, AnyView)] = [
            ("F", AnyView(IconTileCandidate.light)),
            ("G", AnyView(IconTileCandidate.dark))
        ]
        for (name, view) in candidates {
            let renderer = ImageRenderer(content: view.frame(width: 512, height: 512))
            renderer.scale = 1
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
            }
        }
    }
}

enum IconTileCandidate {
    // 与抽屉网格一致的彩色小方块（模拟 App 图标）
    private static let tileColors: [Color] = [
        Color(red: 0.95, green: 0.45, blue: 0.35),
        Color(red: 0.98, green: 0.75, blue: 0.25),
        Color(red: 0.40, green: 0.65, blue: 0.95),
        Color(red: 0.35, green: 0.75, blue: 0.50),
        Color(red: 0.60, green: 0.45, blue: 0.90),
        Color(red: 0.92, green: 0.55, blue: 0.30),
        Color(red: 0.30, green: 0.72, blue: 0.80),
        Color(red: 0.85, green: 0.40, blue: 0.60),
        Color(red: 0.50, green: 0.80, blue: 0.45)
    ]

    private static func miniGrid(tileSize: CGFloat, radius: CGFloat, gap: CGFloat) -> some View {
        VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { col in
                        let i = row * 3 + col
                        RoundedRectangle(cornerRadius: radius)
                            .fill(LinearGradient(colors: [tileColors[i], tileColors[i].opacity(0.8)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: tileSize, height: tileSize)
                            .overlay(RoundedRectangle(cornerRadius: radius)
                                .strokeBorder(Color.white.opacity(0.6), lineWidth: tileSize * 0.05))
                            .shadow(color: .black.opacity(0.18), radius: tileSize * 0.06, y: tileSize * 0.05)
                    }
                }
            }
        }
    }

    // F · 浅色磁贴（和软件里一级的文件夹磁贴同款气质）
    static var light: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 115)
                .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.86)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 115)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 2))
            miniGrid(tileSize: 118, radius: 26, gap: 16)
        }
    }

    // G · 深色磁贴（暗底更衬彩色小方块）
    static var dark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 115)
                .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.10)],
                                     startPoint: .top, endPoint: .bottom))
            miniGrid(tileSize: 118, radius: 26, gap: 16)
        }
    }
}

// MARK: - Dock 真实尺寸预览（DOCKDRAWER_ICON_DOCKSIZE=1）
//
// 把候选设计按 Dock 图标的实际大小（64pt）渲染并放大展示——
// 验证"小尺寸下还认得出是什么"这一关键指标。

enum IconDockSizeRenderer {
    @MainActor
    static func renderAllToDisk(dir: String) {
        let current = NSImage(contentsOf: Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/AppIcon.icns"))
        let candidates: [(String, NSImage?)] = [
            ("A_drawerChest", renderView(IconCandidate.drawerChest)),
            ("C_trayArrow", renderView(IconCandidate.trayArrow)),
            ("D_glowDrawer", renderView(IconCandidate.glowDrawer)),
            ("CURRENT", current)
        ]
        for (name, image) in candidates {
            guard let image else { continue }
            // 先缩到 Dock 真实大小（64px），再放大到 256 供查看
            let small = NSImage(size: NSSize(width: 64, height: 64))
            small.lockFocus()
            image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64),
                       from: .zero, operation: .copy, fraction: 1)
            small.unlockFocus()
            let shown = NSImage(size: NSSize(width: 256, height: 256))
            shown.lockFocus()
            small.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256),
                       from: .zero, operation: .copy, fraction: 1)
            shown.unlockFocus()
            guard let tiff = shown.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: URL(fileURLWithPath: "\(dir)/dock_\(name).png"))
        }
    }

    @MainActor
    private static func renderView(_ view: some View) -> NSImage? {
        let renderer = ImageRenderer(content: view.frame(width: 512, height: 512))
        renderer.scale = 1
        return renderer.nsImage
    }
}
