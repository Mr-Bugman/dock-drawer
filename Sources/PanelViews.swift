import SwiftUI
import UniformTypeIdentifiers

// MARK: - 面板根视图

struct PanelRootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var controller: PanelController
    /// 玻璃上的白色薄雾层（0 = 关；由 PanelController.glassFrost 传入）
    var frost: CGFloat = 0

    var body: some View {
        ZStack {
            if frost > 0 {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(frost))
            }
            switch controller.mode {
            case .folders:
                TopStripView()
            case .drawer(let folderID):
                DrawerView(folderID: folderID)
            }
        }
    }
}

// MARK: - 编辑模式的移除徽章
//
// 用 AppKit 现画的 NSImage（SwiftUI 的语义色在部分离屏渲染路径下解析不可靠，红色会变灰）；
// 手势用 highPriorityGesture——普通 onTapGesture 会被外层格子的手势抢走，导致点不动

struct RemoveBadge: View {
    let action: () -> Void

    static let badgeImage: NSImage = {
        let image = NSImage(size: NSSize(width: 28, height: 28))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 26, height: 26)).fill()
        NSColor.white.setStroke()
        let border = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 26, height: 26))
        border.lineWidth = 1.5
        border.stroke()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 8.5, y: 12.5, width: 11, height: 3),
                     xRadius: 1.5, yRadius: 1.5).fill()
        image.unlockFocus()
        return image
    }()

    var body: some View {
        Image(nsImage: Self.badgeImage)
            .resizable() // 不加这个图片会按原始 28pt 渲染：显示双倍大、点击判定区却只有一半
            .frame(width: 14, height: 14)
            .contentShape(Circle())
            .highPriorityGesture(TapGesture().onEnded { action() })
            .help("移除")
    }
}

// MARK: - 编辑模式的轻微晃动（用 TimelineView 驱动，避免 repeatForever 动画
// 把"徽章出现"也卷进无限循环里，导致徽章永远半透明）

struct WiggleEffect: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = sin(t * 2 * .pi / 0.28) // 0.28 秒一个来回
                content.rotationEffect(.degrees(phase * 2.2))
            }
        } else {
            content
        }
    }
}

// 面板和抽屉的圆角毛玻璃背景由 PanelController 里的 NSGlassEffectView 提供，这里只管内容。

// MARK: - 一级面板（点 Dock 图标弹出的第一层：文件夹和 App 混排，手机桌面式）

struct TopStripView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var controller: PanelController

    // 一行最多 5 个，多了自动换行；只有 66×66 的格子，所以内容是确定性尺寸
    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(66), spacing: 10), count: max(1, min(store.items.count, 5)))
    }

    var body: some View {
        Group {
            if store.items.isEmpty {
                Text("空空如也，点「整理 App」添加")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(24)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case .folder(let folder):
                            FolderIconView(folder: folder, index: index)
                        case .app(let app):
                            AppTileView(app: app, index: index)
                        }
                    }
                }
                .padding(16)
                // 拖拽排序时其他图标流畅让位
                .animation(.spring(response: 0.32, dampingFraction: 0.8),
                           value: store.items.map { $0.id })
            }
        }
        .onDrop(of: [.plainText, .fileURL], isTargeted: nil) { providers in
            DropCoordinator.handle(providers: providers, target: .topSlot(insertIndex: nil))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 点面板空白处：编辑模式下先退出编辑
            if controller.editMode { withAnimation { controller.editMode = false } }
        }
    }
}

// MARK: - 手机风格文件夹图标

struct FolderIconView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var controller: PanelController
    let folder: Folder
    let index: Int

    private var hoverKey: String { "hover/folder/\(folder.id)" }
    private var dropKey: String { "drop/folder/\(folder.id)" }

    private var hovered: Bool { controller.hoverKeys.contains(hoverKey) }
    private var targeted: Bool { controller.dropTargetKeys.contains(dropKey) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cellContent
            if controller.editMode {
                // 兄弟视图，避免点击被格子手势吞掉
                RemoveBadge {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        store.deleteFolder(folder.id)
                    }
                }
                .offset(x: 4, y: -4)
            }
        }
        .frame(width: 66, height: 66)
        .modifier(WiggleEffect(active: controller.editMode))
        .transition(.scale.combined(with: .opacity))
    }

    /// 文件夹图标本体 + 全部手势（⊖ 徽章不在这里，避免手势互相打架）
    /// 灰色磁贴 52×52（与 App 图标的可见尺寸对齐，避免文件夹看着比 App 大），
    /// 点击区域保持 66×66 不变
    @ViewBuilder
    private var cellContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 52, height: 52)
            Group {
                if folder.apps.isEmpty {
                    Image(systemName: "folder")
                        .font(.system(size: 19))
                        .foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(13), spacing: 2), count: 3),
                              spacing: 2) {
                        ForEach(Array(folder.apps.prefix(9))) { app in
                            Image(nsImage: app.displayIcon)
                                .resizable()
                                .frame(width: 13, height: 13)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
            }
            .frame(width: 52, height: 52)
        }
        .frame(width: 66, height: 66)
        .scaleEffect(hovered || targeted ? 1.06 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered || targeted)
        .overlay(RoundedRectangle(cornerRadius: 15)
            .strokeBorder(targeted ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 15))
        .onHover { controller.setHover(hoverKey, $0) }
        .onLongPressGesture(minimumDuration: 0.5) {
            withAnimation { controller.editMode = true }
        }
        .onTapGesture {
            if controller.editMode {
                withAnimation { controller.editMode = false }
            } else {
                controller.openDrawer(for: folder)
            }
        }
        .onDrag {
            DragSessionTracker.shared.beginTopItem(folder.id)
            let provider = NSItemProvider()
            provider.registerObject("dockdrawer-topitem/\(folder.id.uuidString)" as NSString,
                                    visibility: .all)
            return provider
        }
        .onDrop(of: [.plainText, .fileURL], delegate: TopTileDropDelegate(
            itemID: folder.id,
            index: index,
            isFolder: true,
            folderID: folder.id,
            dropKey: dropKey,
            controller: controller))
        .contextMenu {
            Button("打开文件夹") {
                controller.openDrawer(for: folder)
            }
            Button("删除文件夹", role: .destructive) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    store.deleteFolder(folder.id)
                }
            }
        }
        .help("打开「\(folder.name)」；长按进编辑模式；从访达把 App 拖到这里可收入")
    }
}

// MARK: - 一级面板上直接摆放的 App 图标

struct AppTileView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var controller: PanelController
    let app: AppEntry
    let index: Int

    private var hoverKey: String { "hover/app/\(app.id)" }
    private var dropKey: String { "drop/tile/\(app.id)" }

    private var hovered: Bool { controller.hoverKeys.contains(hoverKey) }
    private var targeted: Bool { controller.dropTargetKeys.contains(dropKey) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cellContent
            if controller.editMode {
                // 兄弟视图，避免点击被格子手势吞掉
                RemoveBadge {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        store.removeApp(appID: app.id)
                    }
                }
                .offset(x: 4, y: -4)
            }
        }
        .frame(width: 66, height: 66)
        .overlay(RoundedRectangle(cornerRadius: 15)
            .strokeBorder(targeted ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .modifier(WiggleEffect(active: controller.editMode))
        .transition(.scale.combined(with: .opacity))
    }

    /// 图标本体 + 全部手势（⊖ 徽章不在这里，避免手势互相打架）
    @ViewBuilder
    private var cellContent: some View {
        Image(nsImage: app.displayIcon)
            .resizable()
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            .opacity(app.exists ? 1 : 0.4)
            .frame(width: 66, height: 66)
            .background(RoundedRectangle(cornerRadius: 15)
                .fill(targeted ? Color.accentColor.opacity(0.20) : Color.clear))
            .scaleEffect(hovered || targeted ? 1.06 : 1)
            .animation(.easeOut(duration: 0.12), value: hovered || targeted)
            .contentShape(RoundedRectangle(cornerRadius: 15))
            .onHover { controller.setHover(hoverKey, $0) }
            .onLongPressGesture(minimumDuration: 0.5) {
                withAnimation { controller.editMode = true }
            }
            .onTapGesture {
                if controller.editMode {
                    withAnimation { controller.editMode = false }
                } else {
                    controller.launch(app)
                }
            }
            .onDrag {
                DragSessionTracker.shared.beginTopItem(app.id)
                let provider = NSItemProvider()
                provider.registerObject("dockdrawer-topitem/\(app.id.uuidString)" as NSString,
                                        visibility: .all)
                provider.registerObject(app.url as NSURL, visibility: .all)
                return provider
            }
            .onDrop(of: [.plainText, .fileURL], delegate: TopTileDropDelegate(
                itemID: app.id,
                index: index,
                isFolder: false,
                folderID: nil,
                dropKey: dropKey,
                controller: controller))
            .contextMenu {
                Button("打开 App") {
                    if app.exists { NSWorkspace.shared.open(app.url) }
                }
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
                }
                Button("从第一层移除", role: .destructive) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        store.removeApp(appID: app.id)
                    }
                }
            }
            .help(app.exists ? "\(app.name)（点开启动；拖别的 App 停在上面会合成文件夹）"
                             : "原始 App 不存在（可能已被移动或删除）")
    }
}

// MARK: - 抽屉（点文件夹弹出的第二层：网格与一级同一套逻辑，平滑展开）
//
// 一行最多 5 个、66×66 格子、自动换行（跟一级面板完全一致）；超过 5 行内部纵向滚动。
// 编辑模式徽章、拖拽排序（含拖到返回键上楼）都可用。

struct DrawerView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var controller: PanelController
    let folderID: UUID

    private var folder: Folder? { store.folder(withID: folderID) }
    private var apps: [AppEntry] { folder?.apps ?? [] }

    // 与一级面板同一套网格逻辑
    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(66), spacing: 10), count: max(1, min(apps.count, 5)))
    }
    private var panelWidth: CGFloat {
        let cols = max(1, min(apps.count, 5))
        return CGFloat(cols) * 66 + CGFloat(cols - 1) * 10 + 32 // 左右各 14 内边距
    }
    private var rowHeight: CGFloat { store.showAppNames ? 70 : 66 }
    private var gridRows: Int { Int(ceil(Double(apps.count) / Double(max(1, min(apps.count, 5))))) }
    private var gridHeight: CGFloat {
        CGFloat(max(1, gridRows)) * rowHeight + CGFloat(max(0, gridRows - 1)) * 10
    }
    /// 最多显示 5 行，更多就内部纵向滚动
    private let maxGridHeight: CGFloat = 66 * 5 + 10 * 4

    var body: some View {
        VStack(spacing: 8) {
            header
            if apps.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                            DrawerAppIcon(app: app, folderID: folderID, index: index)
                        }
                    }
                    .padding(.horizontal, 2)
                    // 编辑模式 ⊖ 徽章伸出图标上缘，留出空间不被裁掉
                    .padding(.top, controller.editMode ? 9 : 0)
                }
                .frame(height: min(gridHeight + (controller.editMode ? 9 : 0), maxGridHeight))
                // 拖拽排序时其他图标流畅让位
                .animation(.spring(response: 0.32, dampingFraction: 0.8),
                           value: apps.map { $0.id })
            }
        }
        .padding(14)
        .frame(width: panelWidth)
        .contentShape(Rectangle())
        .onTapGesture {
            // 点抽屉空白处：编辑模式下先退出编辑
            if controller.editMode { withAnimation { controller.editMode = false } }
        }
        .onChange(of: store.folders) { _, _ in
            if folder == nil { controller.showFolders() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            headerButton("chevron.left",
                         "返回上一级（拖 App 到这里可移到第一层）",
                         targeted: controller.dropTargetKeys.contains("drop/back")) {
                controller.showFolders()
            }
            .onDrop(of: [.plainText, .fileURL],
                    delegate: BackButtonDropDelegate(folderID: folderID, controller: controller))
            Spacer()
            Text(folder?.name ?? "")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Spacer()
            headerButton("slider.horizontal.3", "打开整理窗口") { controller.openManager() }
        }
        .frame(height: 28)
    }

    /// 头部圆形小按钮：28×28 的大判定区域，别再只有图标那么一丁点
    private func headerButton(_ systemName: String, _ help: String,
                              targeted: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(Circle().fill(targeted ? Color.accentColor.opacity(0.45)
                                                   : Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("这个文件夹还是空的")
                .font(.system(size: 12, weight: .medium))
            Text("从访达把 App 拖到文件夹图标上，或点「整理 App」添加")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }
}

/// 返回键的落点：拖 App 悬停 0.6 秒自动上楼（拖拽不断，接着在一级里重排）；
/// 直接落在返回键上也移到一级
final class BackButtonDropDelegate: DropDelegate {
    let folderID: UUID
    let controller: PanelController
    private var navWork: DispatchWorkItem?

    init(folderID: UUID, controller: PanelController) {
        self.folderID = folderID
        self.controller = controller
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText, .fileURL])
    }

    func dropEntered(info: DropInfo) {
        controller.setDropTarget("drop/back", true)
        cancelNav()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            navigateUp()
        }
        navWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func dropExited(info: DropInfo) {
        cancelNav()
        controller.setDropTarget("drop/back", false)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            cancelNav()
            controller.setDropTarget("drop/back", false)
            DragSessionTracker.shared.end()
        }
        switch DragSessionTracker.shared.state?.kind {
        case .appInFolder(let sourceFolderID, let appID, _):
            Store.shared.moveApp(appID: appID, to: .top, insertIndex: nil)
            DragSessionTracker.shared.promoteToTopItem(appID)
            controller.showFolders()
            _ = sourceFolderID
            return true
        case .topItem:
            return true // 已在一级
        case nil:
            // 外部拖入的 App：放到第一层
            for provider in info.itemProviders(for: [UTType.fileURL]) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let url = TopTileDropDelegate.decodeURL(item),
                          DropCoordinator.isAppURL(url) else { return }
                    Task { @MainActor in
                        let entry = AppEntry(name: DropCoordinator.displayName(of: url), path: url.path)
                        Store.shared.addApps([entry], to: .top)
                        PanelController.shared.showFolders()
                    }
                }
            }
            return true
        }
    }

    private func navigateUp() {
        // 悬停触发：把正在拖的 App 先移到一级末尾，会话升级为一级条目，落手时可在一级重排
        if case .appInFolder(_, let appID, _)? = DragSessionTracker.shared.state?.kind {
            Store.shared.moveApp(appID: appID, to: .top, insertIndex: nil)
            DragSessionTracker.shared.promoteToTopItem(appID)
        }
        controller.showFolders()
    }

    private func cancelNav() {
        navWork?.cancel()
        navWork = nil
    }
}

// MARK: - 抽屉网格里的 App 图标（样式大小与一级一致）

struct DrawerAppIcon: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var controller: PanelController
    let app: AppEntry
    let folderID: UUID
    let index: Int

    private var hoverKey: String { "hover/drawer/\(app.id)" }
    private var hovered: Bool { controller.hoverKeys.contains(hoverKey) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cellContent
            if controller.editMode {
                // 徽章必须是手势承载层的兄弟视图：挂在它内部时，
                // 点击会被格子的 onDrag/tap 手势吞掉
                RemoveBadge {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        store.removeApp(appID: app.id)
                    }
                }
                .offset(x: 3, y: 3)
            }
        }
        .frame(width: 66, height: store.showAppNames ? 70 : 66)
        .modifier(WiggleEffect(active: controller.editMode))
        .transition(.scale.combined(with: .opacity))
    }

    /// 图标本体 + 全部手势（⊖ 徽章不在这里，避免手势互相打架）
    @ViewBuilder
    private var cellContent: some View {
        VStack(spacing: 3) {
            Image(nsImage: app.displayIcon)
                .resizable()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                .opacity(app.exists ? 1 : 0.4)
            if store.showAppNames {
                Text(app.name)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 62)
                    .foregroundColor(app.exists ? .primary : .secondary)
            }
        }
        .frame(width: 66, height: store.showAppNames ? 70 : 66)
        .scaleEffect(hovered && !controller.editMode ? 1.08 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .contentShape(Rectangle())
        .onHover { controller.setHover(hoverKey, $0) }
        .onLongPressGesture(minimumDuration: 0.5) {
            withAnimation { controller.editMode = true }
        }
        .onTapGesture {
            if controller.editMode {
                withAnimation { controller.editMode = false }
            } else {
                controller.launch(app)
            }
        }
        .onDrag {
            DragSessionTracker.shared.beginApp(inFolder: folderID, app.id, fromDrawer: true)
            let provider = NSItemProvider()
            provider.registerObject("dockdrawer-app/\(folderID.uuidString)/\(app.id.uuidString)" as NSString,
                                    visibility: .all)
            provider.registerObject(app.url as NSURL, visibility: .all)
            return provider
        }
        .onDrop(of: [.plainText, .fileURL], delegate: DrawerCellDropDelegate(
            folderID: folderID,
            index: index))
        .contextMenu {
            Button("打开 App") {
                if app.exists { NSWorkspace.shared.open(app.url) }
            }
            Button("在访达中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            }
            Button("移出该文件夹", role: .destructive) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    store.removeApp(appID: app.id)
                }
            }
        }
        .help(app.exists ? app.name : "原始 App 不存在（可能已被移动或删除）")
    }
}
