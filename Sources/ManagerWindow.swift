import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 整理窗口控制器
//
// 顺带充当整理窗口的瞬时状态仓库（选中的分区、勾选的 App、弹窗开关），
// 因为这套构建环境里 SwiftUI 的 @State 宏插件缺失，状态一律走 ObservableObject。

final class ManagerController: ObservableObject {
    static let shared = ManagerController()

    @Published var selectedContainerID: UUID? = Store.topRowID
    @Published var selectedAppIDs: Set<UUID> = []
    @Published var showAddPanel = false
    @Published var confirmDeleteFolder = false
    @Published var dropTargetKeys: Set<String> = []

    private var window: NSWindow?

    func setDropTarget(_ key: String, _ on: Bool) {
        if on { dropTargetKeys.insert(key) } else { dropTargetKeys.remove(key) }
    }

    func dropBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { [weak self] in self?.dropTargetKeys.contains(key) ?? false },
                set: { [weak self] in self?.setDropTarget(key, $0) })
    }

    func open() {
        PanelController.shared.hide()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "整理 App — Dock 抽屉"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ManagerRootView()
                .environmentObject(Store.shared)
                .environmentObject(self))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 整理窗口

struct ManagerRootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var manager: ManagerController

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear {
            if manager.selectedContainerID == nil { manager.selectedContainerID = Store.topRowID }
        }
        .alert(store.launchAtLoginError ?? "", isPresented: Binding(
            get: { store.launchAtLoginError != nil },
            set: { if !$0 { store.launchAtLoginError = nil } })) {
            Button("好") {}
        } message: {
            Text("可以到「系统设置 → 通用 → 登录项」里手动允许。")
        }
    }

    // MARK: 左侧分区列表（一级 + 各文件夹）

    private var sidebar: some View {
        VStack(spacing: 0) {
            Text("收纳位置")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            List(selection: Binding(
                get: { manager.selectedContainerID },
                set: {
                    manager.selectedContainerID = $0
                    manager.selectedAppIDs = []
                })) {
                // 一级 App：直接摆在弹出面板上的那些
                HStack {
                    Image(systemName: "square.grid.2x2")
                        .foregroundColor(.accentColor)
                    Text("一级 App")
                        .lineLimit(1)
                    Spacer()
                    Text("\(store.topApps.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .tag(Store.topRowID)
                .contentShape(Rectangle())
                .onDrop(of: [.plainText, .fileURL], isTargeted: nil) { providers in
                    DropCoordinator.handle(providers: providers, target: .topSlot(insertIndex: nil))
                }
                .help("直接摆在面板第一层的 App；把 App 拖到这里可添加")

                ForEach(store.folders) { folder in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.accentColor)
                        Text(folder.name)
                            .lineLimit(1)
                        Spacer()
                        Text("\(folder.apps.count)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .tag(folder.id)
                    .contentShape(Rectangle())
                    .onDrop(of: [.plainText, .fileURL], isTargeted: nil) { providers in
                        DropCoordinator.handle(providers: providers,
                                               target: .folder(folder.id, insertIndex: nil))
                    }
                    .help("把 App 拖到这里可收入文件夹；从访达拖 App 到这里可添加")
                }
            }
            .listStyle(.sidebar)

            HStack(spacing: 8) {
                Button {
                    manager.selectedContainerID = store.addFolder()
                    manager.selectedAppIDs = []
                } label: {
                    Label("新建文件夹", systemImage: "plus")
                }
                Button(role: .destructive) {
                    if let id = manager.selectedContainerID, id != Store.topRowID {
                        store.deleteFolder(id)
                    }
                    manager.selectedContainerID = Store.topRowID
                    manager.selectedAppIDs = []
                } label: {
                    Label("删除", systemImage: "minus")
                }
                .disabled(manager.selectedContainerID == nil || manager.selectedContainerID == Store.topRowID)
                Spacer()
            }
            .padding(10)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("设置")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Toggle("图标下显示名称", isOn: Binding(
                    get: { Store.shared.showAppNames },
                    set: { Store.shared.showAppNames = $0 }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Toggle("开机自动启动", isOn: Binding(
                    get: { Store.shared.launchAtLogin },
                    set: { Store.shared.launchAtLogin = $0 }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(10)
        }
    }

    // MARK: 右侧详情

    @ViewBuilder
    private var detail: some View {
        if let containerID = manager.selectedContainerID,
           containerID == Store.topRowID || store.folder(withID: containerID) != nil {
            ContainerDetailView(containerID: containerID)
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 34))
                    .foregroundColor(.secondary)
                Text("先在左边选一个收纳位置")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
}

// MARK: - 单个收纳位置（一级 App 或某个文件夹）的整理页

struct ContainerDetailView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var manager: ManagerController
    let containerID: UUID

    private var isTopRow: Bool { containerID == Store.topRowID }
    private var folder: Folder? { store.folder(withID: containerID) }
    private var apps: [AppEntry] { store.apps(in: isTopRow ? .top : .folder(containerID)) }
    private var container: Store.Container { isTopRow ? .top : .folder(containerID) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if apps.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .onAppear { manager.selectedAppIDs = [] }
        .confirmationDialog("删除文件夹「\(folder?.name ?? "")」？",
                            isPresented: Binding(
                                get: { manager.confirmDeleteFolder },
                                set: { manager.confirmDeleteFolder = $0 }),
                            titleVisibility: .visible) {
            Button("删除（名单里的 App 不会被删掉）", role: .destructive) {
                store.deleteFolder(containerID)
                manager.selectedAppIDs = []
                manager.selectedContainerID = Store.topRowID
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这个文件夹从列表里消失，但里面的 App 本体安然无恙。")
        }
        .fileImporter(isPresented: Binding(
            get: { manager.showAddPanel },
            set: { manager.showAddPanel = $0 }),
            allowedContentTypes: [.application],
            allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let entries = urls.map { url in
                    AppEntry(name: DropCoordinator.displayName(of: url), path: url.path)
                }
                store.addApps(entries, to: container)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if isTopRow {
                Text("一级 App — 直接摆在弹出的面板上")
                    .font(.system(size: 14, weight: .semibold))
            } else {
                TextField("文件夹名称", text: Binding(
                    get: { store.folder(withID: containerID)?.name ?? "" },
                    set: { store.renameFolder(containerID, to: $0) }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: 220)
                Button(role: .destructive) { manager.confirmDeleteFolder = true } label: {
                    Label("删除文件夹", systemImage: "trash")
                }
            }
            Spacer()
            Button { manager.showAddPanel = true } label: {
                Label("添加 App", systemImage: "plus")
            }
            Button(role: .destructive) {
                for id in manager.selectedAppIDs { store.removeApp(appID: id) }
                manager.selectedAppIDs = []
            } label: {
                Label("移除所选", systemImage: "minus")
            }
            .disabled(manager.selectedAppIDs.isEmpty)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(isTopRow
                 ? "把 App 从访达拖到这里，它们会直接摆在面板第一层"
                 : "把 App 从访达拖到这里，或点「添加 App」")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("添加 App") { manager.showAddPanel = true }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.plainText, .fileURL], isTargeted: nil) { providers in
            DropCoordinator.handle(providers: providers, target: isTopRow ? .topSlot(insertIndex: nil) : .folder(containerID, insertIndex: nil))
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    ManagerAppCell(app: app,
                                   containerID: containerID,
                                   index: index,
                                   selected: manager.selectedAppIDs.contains(app.id))
                }
            }
            .padding(12)
        }
    }
}

// MARK: - 整理窗口里的 App 格子

struct ManagerAppCell: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var manager: ManagerController
    let app: AppEntry
    let containerID: UUID
    let index: Int
    let selected: Bool

    private var dropKey: String { "drop/cell/\(app.id)" }
    private var targeted: Bool { manager.dropTargetKeys.contains(dropKey) }

    private var container: Store.Container {
        containerID == Store.topRowID ? .top : .folder(containerID)
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: app.displayIcon)
                .resizable()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .opacity(app.exists ? 1 : 0.4)
            Text(app.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 88)
                .foregroundColor(app.exists ? .primary : .secondary)
        }
        .padding(8)
        .frame(width: 96)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(selected ? Color.accentColor.opacity(0.22)
                            : (targeted ? Color.primary.opacity(0.08) : Color.clear)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(targeted ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if app.exists { NSWorkspace.shared.open(app.url) }
        }
        .onTapGesture {
            if manager.selectedAppIDs.contains(app.id) {
                manager.selectedAppIDs.remove(app.id)
            } else {
                manager.selectedAppIDs.insert(app.id)
            }
        }
        .contextMenu {
            Button("打开 App") {
                if app.exists { NSWorkspace.shared.open(app.url) }
            }
            Button("在访达中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            }
            Button("移除", role: .destructive) {
                store.removeApp(appID: app.id)
                manager.selectedAppIDs.remove(app.id)
            }
        }
        .onDrag {
            DragSessionTracker.shared.beginApp(inFolder: containerID, app.id, fromDrawer: false)
            let provider = NSItemProvider()
            provider.registerObject(DropCoordinator.payloadString(containerID, app.id) as NSString,
                                    visibility: .all)
            provider.registerObject(app.url as NSURL, visibility: .all)
            return provider
        }
        .onDrop(of: [.plainText, .fileURL], isTargeted: manager.dropBinding(dropKey)) { providers in
            DropCoordinator.handle(providers: providers,
                                   target: containerID == Store.topRowID
                                       ? .topSlot(insertIndex: index)
                                       : .folder(containerID, insertIndex: index))
        }
        .help(app.exists ? app.name : "原始 App 不存在（可能已被移动或删除）")
    }
}
