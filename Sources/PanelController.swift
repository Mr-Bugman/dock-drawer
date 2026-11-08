import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 面板状态

enum PanelMode: Equatable {
    case folders
    case drawer(UUID)
}

// MARK: - 无边框悬浮面板

final class DrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc：编辑模式先退出编辑，否则收起面板
            if PanelController.shared.editMode {
                PanelController.shared.editMode = false
            } else {
                PanelController.shared.hide()
            }
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - 面板控制器
//
// 顺带充当面板相关界面的瞬时状态仓库（悬停/拖放高亮、抽屉页码），
// 因为这套构建环境里 SwiftUI 的 @State 宏插件缺失，状态一律走 ObservableObject。

final class PanelController: ObservableObject {
    static let shared = PanelController()

    /// 玻璃质感设置：全透玻璃 + 25% 白雾（作者先选全透后嫌太透，2026-11-08 改定 B 档）
    static var glassStyle: NSGlassEffectView.Style = .clear
    static var glassFrost: CGFloat = 0.25

    @Published private(set) var mode: PanelMode = .folders

    // 面板瞬时 UI 状态
    @Published var editMode = false {
        didSet {
            guard editMode != oldValue else { return }
            // 进出编辑模式：徽章要伸出面板上缘，面板需要加高，平滑过渡
            rebuildContent(animated: true)
        }
    }
    @Published var hoverKeys: Set<String> = []
    @Published var dropTargetKeys: Set<String> = []

    var isDrawerMode: Bool {
        if case .drawer = mode { return true }
        return false
    }

    /// 抽屉单横排允许的最大宽度（按锚点所在屏幕算，rebuildContent 前更新）
    private(set) var drawerMaxWidth: CGFloat = 520

    private var panel: DrawerPanel?
    private var anchorPoint: NSPoint = NSPoint(x: 0, y: 0)
    private var outsideClickStarted: Date?
    /// 最近一次「点外面」引起的收起时间，供 Dock 图标点击事件判断是否要跳过弹回
    private(set) var lastOutsideClickHideAt: Date?
    private var hideWorkItem: DispatchWorkItem?
    private var globalClickMonitor: Any?
    private var localMouseMonitor: Any?

    /// Dock 点击事件发现面板刚被鼠标监听收掉时，消费掉这个标记（别再弹回）
    func consumeOutsideClickHideFlag() {
        lastOutsideClickHideAt = nil
    }

    // MARK: 拖拽悬停"合并待命"（拖 App 停在另一个 App 图标上 0.7 秒 → 落手合成文件夹）
    //
    // 状态挂在控制器单例上，因为落点代理会随界面刷新重建，不能自己记状态。

    private var mergeArmWorks: [String: DispatchWorkItem] = [:]
    private(set) var mergeArmedKey: String?

    func armMerge(key: String, after seconds: Double) {
        cancelMerge(key: key)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.mergeArmedKey = key
            self.setDropTarget(key, true)
        }
        mergeArmWorks[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func cancelMerge(key: String) {
        mergeArmWorks[key]?.cancel()
        mergeArmWorks[key] = nil
        if mergeArmedKey == key {
            mergeArmedKey = nil
            setDropTarget(key, false)
        }
    }

    func consumeMerge(key: String) -> Bool {
        guard mergeArmedKey == key else { return false }
        mergeArmedKey = nil
        return true
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// 调试用：真实面板窗口（截自己窗口不需要屏幕录制权限）
    var panelWindow: NSPanel? { panel }

    private init() {
        installMonitors()
        // 设置变化（比如开关"图标下显示名称"）→ 面板开着就即时平滑刷新
        NotificationCenter.default.addObserver(forName: .dockDrawerPrefChanged,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.refreshPanel()
        }
    }

    // MARK: 瞬时状态的小工具

    func setHover(_ key: String, _ on: Bool) {
        if on { hoverKeys.insert(key) } else { hoverKeys.remove(key) }
    }

    func setDropTarget(_ key: String, _ on: Bool) {
        if on { dropTargetKeys.insert(key) } else { dropTargetKeys.remove(key) }
    }

    func dropBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { [weak self] in self?.dropTargetKeys.contains(key) ?? false },
                set: { [weak self] in self?.setDropTarget(key, $0) })
    }

    // MARK: 显示 / 隐藏

    func show(at point: NSPoint) {
        let panel = makePanelIfNeeded()
        anchorPoint = point
        outsideClickStarted = nil
        lastOutsideClickHideAt = nil
        cancelScheduledHide()
        mode = .folders
        rebuildContent()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
        if editMode { editMode = false }
    }

    func openDrawer(for folder: Folder) {
        mode = .drawer(folder.id)
        rebuildContent(animated: true)
    }

    func showFolders() {
        mode = .folders
        rebuildContent(animated: true)
    }

    func launch(_ app: AppEntry) {
        guard app.exists else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(app.url)
        hide()
    }

    func openManager() {
        ManagerController.shared.open()
    }

    /// 调试用：把面板当前内容渲染成 PNG（不依赖系统的屏幕录制权限）
    @discardableResult
    func snapshot(to path: String) -> Bool {
        guard let panel, let view = panel.contentView else { return false }
        return Self.render(view: view, to: path)
    }

    static func render(view: NSView, to path: String) -> Bool {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            NSLog("DockDrawer snapshot error: \(error)")
            return false
        }
    }

    // MARK: 面板搭建

    private func makePanelIfNeeded() -> DrawerPanel {
        if let panel { return panel }
        let panel = DrawerPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }

    func refreshPanel() {
        guard isVisible else { return }
        rebuildContent(animated: true)
    }

    /// 按当前模式重建内容并重新定位面板；animated = true 时面板尺寸平滑过渡 + 内容淡入
    private func rebuildContent(animated: Bool = false) {
        guard let panel else { return }
        // 抽屉最大宽度按锚点所在屏幕先算好（SwiftUI 布局时要读）
        let screen = NSScreen.screens.first { NSMouseInRect(anchorPoint, $0.frame, false) } ?? NSScreen.main
        drawerMaxWidth = (screen?.visibleFrame.width ?? 1280) - 24

        let root = PanelRootView(frost: PanelController.glassFrost)
            .environmentObject(Store.shared)
            .environmentObject(self)
        let hosting = NSHostingView(rootView: root)
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        size.width = max(size.width, 150)
        size.height = max(size.height, 90)

        // 玻璃主体（小尾巴方案已放弃：系统玻璃部件既不支持旋转也不支持遮罩裁剪）
        let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0,
                                                    width: size.width,
                                                    height: size.height))
        glass.cornerRadius = 20
        glass.style = PanelController.glassStyle
        glass.effectIsInteractive = true
        hosting.frame = NSRect(origin: .zero, size: size)
        glass.contentView = hosting
        panel.contentView = glass

        let newFrame = frameFor(size: size)
        if animated {
            glass.alphaValue = 0
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                glass.animator().alphaValue = 1
                panel.animator().setFrame(newFrame, display: true)
            })
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }

    /// 把面板底边锚在目标点上方（一般是 Dock 图标位置），并夹在屏幕可见范围内
    private func frameFor(size: NSSize) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(anchorPoint, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        var originX = anchorPoint.x - size.width / 2
        originX = max(visible.minX + 8, min(originX, visible.maxX - size.width - 8))
        var originY = anchorPoint.y + 20
        originY = max(visible.minY + 4, min(originY, visible.maxY - size.height - 4))
        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    // MARK: 点外面收起
    //
    // 普通点击：松开鼠标那一刻立即收起。
    // 按住拖拽（比如从访达拖 App 过来）：不算点击，不会误收。

    private func installMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                       .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handleOutsideEvent(event)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown]) { [weak self] event in
            self?.handleOutsideEvent(event, isLocal: true)
            return event
        }
    }

    private func handleOutsideEvent(_ event: NSEvent, isLocal: Bool = false) {
        if event.type == .leftMouseUp {
            DragSessionTracker.shared.end() // 任何松手都终结拖拽会话（包括面板内部松手）
        }
        guard isVisible else { return }
        if isLocal, event.window === panel { return } // 点面板自己，不归这里管
        switch event.type {
        case .leftMouseDown:
            outsideClickStarted = Date()
            // 双保险：mouseUp 事件偶尔不送达监听器（比如会激活别的窗口的点击），
            // 所以点下 0.15 秒后自动收——到点时键已松开才收。
            scheduleClickHide(0.15)
        case .leftMouseUp:
            cancelScheduledHide()
            guard let started = outsideClickStarted else {
                // 没有在计时的点击 = 一场拖拽刚结束（拖拽会话会吞掉 mouseUp，
                // 能收到 mouseUp 说明不是拖拽）；面板若还开着但丢了焦点，重新设为 key 恢复
                restoreKeyIfNeeded()
                return
            }
            outsideClickStarted = nil
            // 松开即收（唯一不收的场景：到 0.15 秒时键还按着 = 持续按住）
            lastOutsideClickHideAt = Date()
            hide()
        case .rightMouseDown, .otherMouseDown:
            hide()
        default:
            break
        }
    }

    /// 点下后的自动收起兜底：到点时若鼠标键已全部松开就收起；
    /// 键还按着（持续按住/拖拽中）就不收——这是唯一的不收场景
    private func scheduleClickHide(_ delay: TimeInterval) {
        cancelScheduledHide()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible else { return }
            guard NSEvent.pressedMouseButtons == 0 else { return }
            self.lastOutsideClickHideAt = Date()
            self.hide()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    /// 拖拽结束后面板还开着但已不是 key，玻璃会退成"未激活"的磨砂观感；把它重新设为 key
    private func restoreKeyIfNeeded() {
        guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
        panel.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 拖放目标描述

enum DropTarget {
    case folder(UUID, insertIndex: Int?)      // 放进某个文件夹（nil 序号 = 追加到末尾）
    case topSlot(insertIndex: Int?)           // 放到一级面板 / 整理窗口的「一级 App」
    case appTile(appID: UUID)                 // 放到一级面板的某个 App 图标上 → 拼合成新文件夹
}

// MARK: - 拖放解析（面板和整理窗口共用）
//
// 支持两种拖入：
// 1. 软件内部的整理拖拽：纯文本标记 "dockdrawer-move/<来源容器ID>/<AppID>"（容器 = 一级哨兵 ID 或文件夹 ID）
// 2. 从访达等外部拖入：file URL，必须是 .app 后缀

enum DropCoordinator {
    static let moveMarkerPrefix = "dockdrawer-move/"

    static func payloadString(_ containerID: UUID, _ appID: UUID) -> String {
        "\(moveMarkerPrefix)\(containerID.uuidString)/\(appID.uuidString)"
    }

    static func parseMoveMarker(_ string: String) -> (containerID: UUID, appID: UUID)? {
        guard string.hasPrefix(moveMarkerPrefix) else { return nil }
        let body = string.dropFirst(moveMarkerPrefix.count)
        let parts = body.split(separator: "/")
        guard parts.count == 2,
              let containerID = UUID(uuidString: String(parts[0])),
              let appID = UUID(uuidString: String(parts[1])) else { return nil }
        return (containerID, appID)
    }

    static func handle(providers: [NSItemProvider], target: DropTarget) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let string = decodeString(item)
                if let string, let marker = parseMoveMarker(string) {
                    Task { @MainActor in
                        handleMoveMarker(marker, target: target)
                    }
                    return
                }
                // 不是内部标记，尝试当作外部文件拖入
                loadAppURL(from: provider) { url in
                    guard let url, isAppURL(url) else {
                        if url != nil { NSSound.beep() } // 拖来的不是 App，拒绝
                        return
                    }
                    Task { @MainActor in
                        handleExternal(url, target: target)
                    }
                }
            }
        }
        return true
    }

    @MainActor
    private static func handleMoveMarker(_ marker: (containerID: UUID, appID: UUID), target: DropTarget) {
        switch target {
        case .folder(let folderID, let insertIndex):
            Store.shared.moveApp(appID: marker.appID, to: .folder(folderID), insertIndex: insertIndex)
        case .topSlot(let insertIndex):
            Store.shared.moveApp(appID: marker.appID, to: .top, insertIndex: insertIndex)
        case .appTile(let targetAppID):
            Store.shared.mergeAppsIntoNewFolder(targetAppID: targetAppID, draggedAppID: marker.appID)
        }
    }

    @MainActor
    private static func handleExternal(_ url: URL, target: DropTarget) {
        let entry = AppEntry(name: displayName(of: url), path: url.path)
        switch target {
        case .folder(let folderID, _):
            Store.shared.addApps([entry], to: .folder(folderID))
        case .topSlot:
            Store.shared.addApps([entry], to: .top)
        case .appTile(let targetAppID):
            Store.shared.mergeExternalApp(entry, ontoAppID: targetAppID)
        }
    }

    private static func decodeString(_ item: Any?) -> String? {
        if let string = item as? String { return string }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        if let attributed = item as? NSAttributedString { return attributed.string }
        return nil
    }

    private static func loadAppURL(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            completion(nil)
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let direct = item as? URL {
                url = direct
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let string = item as? String {
                url = URL(string: string) ?? URL(fileURLWithPath: string)
            }
            completion(url)
        }
    }

    static func displayName(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// 只有 .app 结尾的才算 App（收 App 是这次说好的边界）
    static func isAppURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app"
    }
}

// MARK: - 拖拽会话（记住本次拖的是什么，各落点据此决定"让位 / 移入 / 合并"）
//
// .onDrag 闭包里 begin；松手（鼠标监听收到 mouseUp）或落手成功后 end。
// 从访达等外部拖进来的没有 begin，state 为 nil = 外部拖入。

final class DragSessionTracker {
    static let shared = DragSessionTracker()

    enum Kind {
        case topItem(UUID)                                    // 一级条目（文件夹或 App），值为条目 id
        case appInFolder(folderID: UUID, appID: UUID, fromDrawer: Bool) // 文件夹里的 App（fromDrawer 标记来源，落点行为不同）
    }
    struct State { let kind: Kind }

    private(set) var state: State?

    func beginTopItem(_ itemID: UUID) { state = State(kind: .topItem(itemID)) }
    func beginApp(inFolder folderID: UUID, _ appID: UUID, fromDrawer: Bool) {
        state = State(kind: .appInFolder(folderID: folderID, appID: appID, fromDrawer: fromDrawer))
    }
    /// 拖到返回键上楼后：App 已移入一级，把会话升级为一级条目，后续可实时重排
    func promoteToTopItem(_ itemID: UUID) { state = State(kind: .topItem(itemID)) }
    func end() {
        state = nil
        Store.shared.flushPersist() // 拖拽结束：把让位排序的结果立刻落盘
    }

    var appID: UUID? {
        if case .appInFolder(_, let appID, _)? = state?.kind { return appID }
        return nil
    }
}

// MARK: - 一级瓦片的落点代理（实时让位 + 悬停合并 + 收进文件夹）
//
// 行为表：
//  · 拖的是一级条目、目标是 App 瓦片   → 实时让位；停 0.7 秒进入"合并待命"，落手合成文件夹
//  · 拖的是一级条目、目标是文件夹图标 → 不让位，高亮；落手把 App 收进该文件夹（文件夹拖到文件夹 = 无操作）
//  · 拖的是文件夹里的 App             → 高亮；落手按目标类型"收进文件夹 / 合成新文件夹"
//  · 从访达拖来的 App                 → 落手时收进文件夹 / 合成新文件夹

final class TopTileDropDelegate: DropDelegate {
    let itemID: UUID
    let index: Int
    let isFolder: Bool
    let folderID: UUID?
    let dropKey: String
    let controller: PanelController

    init(itemID: UUID, index: Int, isFolder: Bool, folderID: UUID?,
         dropKey: String, controller: PanelController) {
        self.itemID = itemID
        self.index = index
        self.isFolder = isFolder
        self.folderID = folderID
        self.dropKey = dropKey
        self.controller = controller
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText, .fileURL])
    }

    func dropEntered(info: DropInfo) {
        let tracker = DragSessionTracker.shared
        switch tracker.state?.kind {
        case .topItem(let draggedID):
            if draggedID != itemID {
                if !isFolder {
                    // 同级让位（App 瓦片之间、以及拖到 App 位置上）
                    if let current = Store.shared.items.firstIndex(where: { $0.id == draggedID }),
                       current != index {
                        Store.shared.moveTopItem(itemID: draggedID, toIndex: index)
                    }
                    // 拖的是 App 且压在另一个 App 图标上：停 0.7 秒进入合并待命
                    if Self.isAppItem(draggedID) {
                        controller.armMerge(key: dropKey, after: 0.7)
                    }
                } else {
                    // 压在文件夹图标上：高亮提示可收进去
                    controller.setDropTarget(dropKey, true)
                }
            }
        case .appInFolder:
            controller.setDropTarget(dropKey, true)
        case nil:
            break // 外部拖入：不做悬停动作，落手时处理
        }
    }

    func dropExited(info: DropInfo) {
        controller.cancelMerge(key: dropKey)
        controller.setDropTarget(dropKey, false)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            controller.cancelMerge(key: dropKey)
            controller.setDropTarget(dropKey, false)
            DragSessionTracker.shared.end()
        }
        let tracker = DragSessionTracker.shared
        switch tracker.state?.kind {
        case .topItem(let draggedID):
            if !isFolder, draggedID != itemID,
               controller.consumeMerge(key: dropKey),
               Self.isAppItem(draggedID) {
                Store.shared.mergeAppsIntoNewFolder(targetAppID: itemID, draggedAppID: draggedID)
            }
            return true
        case .appInFolder(_, let draggedAppID, let fromDrawer):
            if fromDrawer {
                // 从抽屉拖出来的：拖到一级瓦片上 = 移到第一层该位置
                Store.shared.moveApp(appID: draggedAppID, to: .top, insertIndex: nil)
            } else if isFolder, let folderID = folderID {
                Store.shared.moveApp(appID: draggedAppID, to: .folder(folderID), insertIndex: nil)
            } else {
                Store.shared.mergeAppsIntoNewFolder(targetAppID: itemID, draggedAppID: draggedAppID)
            }
            return true
        case nil:
            // 外部拖入的 App 文件
            for provider in info.itemProviders(for: [UTType.fileURL]) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let url = Self.decodeURL(item), DropCoordinator.isAppURL(url) else {
                        if Self.decodeURL(item) != nil { NSSound.beep() }
                        return
                    }
                    Task { @MainActor in
                        let entry = AppEntry(name: DropCoordinator.displayName(of: url), path: url.path)
                        if self.isFolder, let folderID = self.folderID {
                            Store.shared.addApps([entry], to: .folder(folderID))
                        } else {
                            Store.shared.mergeExternalApp(entry, ontoAppID: self.itemID)
                        }
                    }
                }
            }
            return true
        }
    }

    private static func isAppItem(_ id: UUID) -> Bool {
        guard let item = Store.shared.items.first(where: { $0.id == id }) else { return false }
        if case .app = item { return true }
        return false
    }

    static func decodeURL(_ item: Any?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) ?? URL(fileURLWithPath: string) }
        return nil
    }
}

// MARK: - 抽屉单横排的落点代理（实时让位 + 移入）

final class DrawerCellDropDelegate: DropDelegate {
    let folderID: UUID
    let index: Int

    init(folderID: UUID, index: Int) {
        self.folderID = folderID
        self.index = index
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText, .fileURL])
    }

    func dropEntered(info: DropInfo) {
        // 同文件夹内的 App：实时让位。异源（别的文件夹/一级/外部）等落手时处理
        if case .appInFolder(let sourceFolderID, let draggedAppID, _)? = DragSessionTracker.shared.state?.kind,
           sourceFolderID == folderID,
           let location = Store.shared.locate(appID: draggedAppID),
           location.seqIndex != index {
            Store.shared.moveApp(appID: draggedAppID, to: .folder(folderID), insertIndex: index)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { DragSessionTracker.shared.end() }
        switch DragSessionTracker.shared.state?.kind {
        case .appInFolder(let sourceFolderID, let draggedAppID, _):
            if sourceFolderID == folderID {
                return true // 已实时排好
            }
            Store.shared.moveApp(appID: draggedAppID, to: .folder(folderID), insertIndex: index)
            return true
        case .topItem(let draggedItemID):
            if let item = Store.shared.items.first(where: { $0.id == draggedItemID }),
               case .app(let app) = item {
                Store.shared.moveApp(appID: app.id, to: .folder(folderID), insertIndex: index)
            }
            return true
        case nil:
            for provider in info.itemProviders(for: [UTType.fileURL]) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let url = TopTileDropDelegate.decodeURL(item),
                          DropCoordinator.isAppURL(url) else {
                        if TopTileDropDelegate.decodeURL(item) != nil { NSSound.beep() }
                        return
                    }
                    Task { @MainActor in
                        let entry = AppEntry(name: DropCoordinator.displayName(of: url), path: url.path)
                        Store.shared.addApps([entry], to: .folder(self.folderID))
                    }
                }
            }
            return true
        }
    }
}
