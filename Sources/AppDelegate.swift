import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 记录启动瞬间系统的开机时长，用来判断是不是开机自动启动的（自启动一般在开机后一两分钟内发生）
    private let launchUptime = ProcessInfo.processInfo.systemUptime

    /// 调试开关读取：优先进程环境变量，其次 `defaults write com.chai.dockdrawer <key> <value>`
    /// （直接 exec 带环境变量偶尔会被 LaunchServices 重新拉起而丢失，defaults 最稳）
    static func debugValue(_ key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key] { return env }
        return UserDefaults.standard.string(forKey: key)
    }

    /// 动态 Dock 图标的延迟刷新（名单变化后 0.4 秒再更新，避免频繁重绘）
    private var iconUpdateWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Store.shared
        buildMainMenu()

        // 调试用：桌面中央并排摆出几种玻璃质感小面板，供真人对比挑选
        if Self.debugValue("DOCKDRAWER_GLASS_PREVIEW") == "1" {
            GlassPreview.show()
            return
        }

        // 调试用：把各种气泡形状直接渲染成 PNG 后退出（不依赖屏幕显示）
        if let dir = Self.debugValue("DOCKDRAWER_BUBBLE_SNAPSHOT_ONLY") {
            BubblePreviewRenderer.renderAllToDisk(dir: dir)
            NSApp.terminate(nil)
        }

        // 调试用：把应用图标候选渲染成 PNG 后退出（不依赖屏幕显示）
        if let dir = Self.debugValue("DOCKDRAWER_ICON_PREVIEW") {
            IconPreviewRenderer.renderAllToDisk(dir: dir)
            IconTileRenderer.renderAllToDisk(dir: dir)
            NSApp.terminate(nil)
        }

        // 调试用：候选图标按 Dock 真实尺寸（64pt）渲染后放大展示
        if let dir = Self.debugValue("DOCKDRAWER_ICON_DOCKSIZE") {
            IconDockSizeRenderer.renderAllToDisk(dir: dir)
            NSApp.terminate(nil)
        }

        let launchedAtLogin = launchUptime < 180
        let debugManager = Self.debugValue("DOCKDRAWER_DEBUG_MANAGER") == "1"
        let debugDrawerName = Self.debugValue("DOCKDRAWER_DEBUG_DRAWER")

        if debugManager {
            ManagerController.shared.open()
        } else if let debugDrawerName {
            // 调试用：启动后直接弹出面板，可指定某个文件夹名直接进抽屉（"first" = 第一个）
            PanelController.shared.show(at: NSEvent.mouseLocation)
            if debugDrawerName != "first" {
                if let folder = Store.shared.items.first(where: {
                    if case .folder(let f) = $0 { return f.name == debugDrawerName }
                    return false
                }), case .folder(let f) = folder {
                    PanelController.shared.openDrawer(for: f)
                }
            }
        } else if !launchedAtLogin {
            // 什么都没放时，第一次打开主动带用户去整理
            let firstLevelEmpty = Store.shared.items.allSatisfy { item in
                if case .folder(let folder) = item { return folder.apps.isEmpty }
                return false
            }
            if firstLevelEmpty {
                ManagerController.shared.open()
            } else {
                PanelController.shared.show(at: NSEvent.mouseLocation)
            }
        }

        // 调试用：启动后把界面渲染成 PNG 再退出，便于自动验收
        if let snapshotOut = Self.debugValue("DOCKDRAWER_SNAPSHOT_OUT") {
            let target = Self.debugValue("DOCKDRAWER_SNAPSHOT") ?? "panel"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                switch target {
                case "manager":
                    ManagerController.shared.open()
                case "drawer":
                    PanelController.shared.show(at: NSPoint(x: 600, y: 200))
                    if let first = Store.shared.items.first, case .folder(let f) = first {
                        PanelController.shared.openDrawer(for: f)
                    }
                case "drawer-edit":
                    PanelController.shared.show(at: NSPoint(x: 600, y: 200))
                    if let first = Store.shared.items.first, case .folder(let f) = first {
                        PanelController.shared.openDrawer(for: f)
                    }
                    PanelController.shared.editMode = true
                case "panel-edit":
                    PanelController.shared.show(at: NSPoint(x: 600, y: 200))
                    PanelController.shared.editMode = true
                case "window-shot":
                    PanelController.shared.show(at: NSPoint(x: 600, y: 200))
                    if let first = Store.shared.items.first, case .folder(let f) = first {
                        PanelController.shared.openDrawer(for: f)
                    }
                case "window-shot-panel":
                    PanelController.shared.show(at: NSPoint(x: 600, y: 200))
                case "drawer-empty":
                    PanelController.shared.show(at: NSPoint(x: 600, y: 200))
                    if let empty = Store.shared.items.first(where: {
                        if case .folder(let f) = $0 { return f.apps.isEmpty }
                        return false
                    }), case .folder(let f) = empty {
                        PanelController.shared.openDrawer(for: f)
                    }
                default:
                    PanelController.shared.show(at: NSPoint(x: 600, y: 200))
                }
                // 再等一拍让 SwiftUI 把编辑模式徽章等变化画完，然后统一截图退出
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    switch target {
                    case "manager":
                        if let view = NSApp.windows.first(where: { $0.title.contains("整理 App") })?.contentView {
                            _ = PanelController.render(view: view, to: snapshotOut)
                        }
                    case "appicon":
                        // 当前锁定的应用图标（Resources/AppIcon.icns 的 512 视图）
                        if let image = NSImage(contentsOf: Bundle.main.bundleURL
                            .appendingPathComponent("Contents/Resources/AppIcon.icns")),
                           let tiff = image.tiffRepresentation,
                           let rep = NSBitmapImageRep(data: tiff),
                           let png = rep.representation(using: .png, properties: [:]) {
                            try? png.write(to: URL(fileURLWithPath: snapshotOut))
                        }
                    default:
                        _ = PanelController.shared.snapshot(to: snapshotOut)
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// 退出前把未落盘的名单改动写盘
    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.flushPersist()
    }

    /// 点 Dock 图标时调用：面板开着就收起，没开就弹出
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if PanelController.shared.isVisible {
            PanelController.shared.hide()
        } else if let at = PanelController.shared.lastOutsideClickHideAt,
                  Date().timeIntervalSince(at) < 0.3 {
            // 这次 Dock 点击的「松开鼠标」刚被鼠标监听/兜底定时器先收掉了（收了又弹回的病根），
            // 别再弹回来
            PanelController.shared.consumeOutsideClickHideFlag()
        } else {
            PanelController.shared.show(at: NSEvent.mouseLocation)
        }
        return true
    }

    /// Dock 图标右键菜单
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let manager = NSMenuItem(title: "整理 App…", action: #selector(openManager(_:)), keyEquivalent: "")
        manager.target = self
        let auto = NSMenuItem(title: "开机自动启动", action: #selector(toggleAutoStart(_:)), keyEquivalent: "")
        auto.target = self
        auto.state = Store.shared.launchAtLogin ? .on : .off
        menu.addItem(manager)
        menu.addItem(auto)
        return menu
    }

    @objc func openManager(_ sender: Any?) {
        ManagerController.shared.open()
    }

    @objc func toggleAutoStart(_ sender: Any?) {
        Store.shared.launchAtLogin.toggle()
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)

        let appMenu = NSMenu(title: "Dock 抽屉")
        let about = NSMenuItem(title: "关于 Dock 抽屉",
                               action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                               keyEquivalent: "")
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let managerItem = NSMenuItem(title: "整理 App…", action: #selector(openManager(_:)), keyEquivalent: ",")
        managerItem.target = self
        appMenu.addItem(managerItem)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Dock 抽屉",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}
