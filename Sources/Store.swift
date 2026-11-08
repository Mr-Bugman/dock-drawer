import AppKit
import ServiceManagement

/// 设置变化的全局通知（Store 不反向依赖界面层，界面自己监听刷新）
extension Notification.Name {
    static let dockDrawerPrefChanged = Notification.Name("com.chai.dockdrawer.prefChanged")
}

// MARK: - 数据模型

struct AppEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var path: String

    var url: URL { URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    /// 图标缓存：每次界面刷新都拿同一张图，避免悬停放大时图片重载导致闪烁
    private static let iconCache = NSCache<NSString, NSImage>()

    var displayIcon: NSImage {
        if let cached = Self.iconCache.object(forKey: path as NSString) {
            return cached
        }
        let image: NSImage
        if exists {
            image = NSWorkspace.shared.icon(forFile: path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        image.size = NSSize(width: 128, height: 128)
        Self.iconCache.setObject(image, forKey: path as NSString)
        return image
    }
}

struct Folder: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var apps: [AppEntry] = []
}

/// 第一层面板上的一个格子：要么是文件夹，要么是直接摆放的 App（手机桌面式混排）
enum TopItem: Hashable, Identifiable {
    case folder(Folder)
    case app(AppEntry)

    var id: UUID {
        switch self {
        case .folder(let folder): return folder.id
        case .app(let app): return app.id
        }
    }
}

// 手写编解码：让 config.json 是干净的 {"folder": {...}} / {"app": {...}}，
// 而不是 Swift 自动合成的 {"folder": {"_0": {...}}}
extension TopItem: Codable {
    private enum CodingKeys: String, CodingKey { case folder; case app }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let folder = try? container.decode(Folder.self, forKey: .folder) {
            self = .folder(folder)
            return
        }
        if let app = try? container.decode(AppEntry.self, forKey: .app) {
            self = .app(app)
            return
        }
        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "无法识别的条目（既不是 folder 也不是 app）"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .folder(let folder): try container.encode(folder, forKey: .folder)
        case .app(let app): try container.encode(app, forKey: .app)
        }
    }
}

// MARK: - 数据仓库

final class Store: ObservableObject {
    static let shared = Store()

    /// 整理窗口里代表「一级 App」的哨兵 ID（直接摆在面板上的 App 们）
    static let topRowID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// App 存放的位置：一级面板，或某个文件夹里
    enum Container: Hashable {
        case top
        case folder(UUID)
    }

    @Published private(set) var items: [TopItem] = []

    @Published var launchAtLogin: Bool = {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }() {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }

    @Published var launchAtLoginError: String?

    /// 抽屉图标下要不要显示 App 名称（记忆在 UserDefaults，默认显示）
    @Published var showAppNames: Bool = UserDefaults.standard.object(forKey: "showAppNames") as? Bool ?? true {
        didSet {
            guard showAppNames != oldValue else { return }
            UserDefaults.standard.set(showAppNames, forKey: "showAppNames")
            NotificationCenter.default.post(name: .dockDrawerPrefChanged, object: nil)
        }
    }

    private var isRestoring = false

    private var dataDirectory: URL {
        // 测试时可用环境变量或 defaults 把数据指到别处，避免动到真实名单
        let custom = ProcessInfo.processInfo.environment["DOCKDRAWER_DATA_DIR"]
            ?? UserDefaults.standard.string(forKey: "DOCKDRAWER_DATA_DIR")
        if let custom {
            let dir = URL(fileURLWithPath: custom, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DockDrawer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var dataFile: URL { dataDirectory.appendingPathComponent("config.json") }

    private init() {
        restore()
        if items.isEmpty {
            items = [.folder(Folder(name: "常用"))]
        }
    }

    // MARK: 读写盘

    private func restore() {
        isRestoring = true
        defer { isRestoring = false }
        guard let data = try? Data(contentsOf: dataFile),
              let loaded = try? JSONDecoder().decode([TopItem].self, from: data) else { return }
        items = loaded
    }

    /// 落盘改为防抖：拖拽实时让位时每次都在主线程写盘会卡顿，
    /// 改成"改内存 + 0.35 秒后统一落盘"；拖拽结束/收面板/退出时立即冲刷
    private var persistWork: DispatchWorkItem?
    private var isDirty = false

    private func persist() {
        guard !isRestoring else { return }
        isDirty = true
        persistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistNow() }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func persistNow() {
        guard isDirty, !isRestoring else { return }
        isDirty = false
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: dataFile, options: [.atomic])
    }

    /// 立即把未落盘的改动写盘（拖拽结束、面板收起、退出时调用）
    func flushPersist() {
        persistWork?.cancel()
        persistWork = nil
        persistNow()
    }

    // MARK: 查询

    func folder(withID id: UUID) -> Folder? {
        for item in items {
            if case .folder(let folder) = item, folder.id == id { return folder }
        }
        return nil
    }

    /// 一级面板上直接摆放的 App（按面板顺序）
    var topApps: [AppEntry] {
        items.compactMap { item in
            if case .app(let app) = item { return app }
            return nil
        }
    }

    /// 所有文件夹（按面板顺序）
    var folders: [Folder] {
        items.compactMap { item in
            if case .folder(let folder) = item { return folder }
            return nil
        }
    }

    func apps(in container: Container) -> [AppEntry] {
        switch container {
        case .top: return topApps
        case .folder(let id): return folder(withID: id)?.apps ?? []
        }
    }

    struct AppLocation {
        let app: AppEntry
        let container: Container
        let seqIndex: Int   // 在所在容器里的序号
        let itemIndex: Int? // 一级 App 才有：在 items 里的下标
    }

    func locate(appID: UUID) -> AppLocation? {
        var topSeq = 0
        for (index, item) in items.enumerated() {
            switch item {
            case .folder(let folder):
                if let j = folder.apps.firstIndex(where: { $0.id == appID }) {
                    return AppLocation(app: folder.apps[j], container: .folder(folder.id),
                                       seqIndex: j, itemIndex: index)
                }
            case .app(let app):
                if app.id == appID {
                    return AppLocation(app: app, container: .top, seqIndex: topSeq, itemIndex: index)
                }
                topSeq += 1
            }
        }
        return nil
    }

    private func folderItemIndex(_ id: UUID) -> Int? {
        items.firstIndex { item in
            if case .folder(let folder) = item { return folder.id == id }
            return false
        }
    }

    private func topItemIndices() -> [Int] {
        items.indices.filter { index in
            if case .app = items[index] { return true }
            return false
        }
    }

    // MARK: 增删改

    @discardableResult
    func addFolder(named name: String = "新建文件夹") -> UUID {
        let folder = Folder(name: name)
        items.append(.folder(folder))
        persist()
        return folder.id
    }

    func deleteFolder(_ id: UUID) {
        items.removeAll { item in
            if case .folder(let folder) = item { return folder.id == id }
            return false
        }
        persist()
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let index = folderItemIndex(id) else { return }
        guard case .folder(var folder) = items[index] else { return }
        guard folder.name != name else { return }
        folder.name = name
        items[index] = .folder(folder)
        persist()
    }

    func addApps(_ newApps: [AppEntry], to container: Container) {
        switch container {
        case .top:
            var existing = Set(topApps.map { $0.path })
            for app in newApps where !existing.contains(app.path) {
                existing.insert(app.path)
                items.append(.app(app))
            }
        case .folder(let folderID):
            guard let index = folderItemIndex(folderID),
                  case .folder(var folder) = items[index] else { return }
            var existing = Set(folder.apps.map { $0.path })
            for app in newApps where !existing.contains(app.path) {
                existing.insert(app.path)
                folder.apps.append(app)
            }
            items[index] = .folder(folder)
        }
        persist()
    }

    func removeApp(appID: UUID) {
        removeAppInternal(appID)
        persist()
    }

    private func removeAppInternal(_ appID: UUID) {
        guard let location = locate(appID: appID) else { return }
        switch location.container {
        case .top:
            if let itemIndex = location.itemIndex, items[itemIndex].id == appID {
                items.remove(at: itemIndex)
            }
        case .folder(let folderID):
            guard let index = folderItemIndex(folderID),
                  case .folder(var folder) = items[index] else { return }
            folder.apps.removeAll { $0.id == appID }
            items[index] = .folder(folder)
        }
    }

    /// 移动 App：容器内排序、跨容器搬移都走这里
    func moveApp(appID: UUID, to destination: Container, insertIndex: Int?) {
        guard let location = locate(appID: appID) else { return }
        let app = location.app
        removeAppInternal(appID)

        switch destination {
        case .top:
            let indices = topItemIndices()
            let target = min(max(0, insertIndex ?? indices.count), indices.count)
            if target < indices.count {
                items.insert(.app(app), at: indices[target])
            } else {
                items.append(.app(app))
            }
        case .folder(let folderID):
            if let index = folderItemIndex(folderID),
               case .folder(var folder) = items[index] {
                let target = min(max(0, insertIndex ?? folder.apps.count), folder.apps.count)
                folder.apps.insert(app, at: target)
                items[index] = .folder(folder)
            } else {
                items.append(.app(app)) // 目标文件夹没了，退回一级兜底
            }
        }
        persist()
    }

    /// 第一层内拖拽排序：把某个条目（文件夹或 App）挪到指定下标的位置
    func moveTopItem(itemID: UUID, toIndex: Int) {
        guard let fromIndex = items.firstIndex(where: { $0.id == itemID }) else { return }
        guard fromIndex != toIndex else { return }
        let item = items.remove(at: fromIndex)
        items.insert(item, at: max(0, min(toIndex, items.count)))
        persist()
    }

    /// 手机式拼合：把一个 App 拖到一级面板的另一个 App 图标上 → 合成新文件夹，替原来那个 App 的位置
    func mergeAppsIntoNewFolder(targetAppID: UUID, draggedAppID: UUID) {
        guard targetAppID != draggedAppID else { return }
        guard let target = locate(appID: targetAppID), target.container == .top,
              let targetItemIndex = target.itemIndex else { return }
        guard let dragged = locate(appID: draggedAppID) else { return }

        var members: [AppEntry] = [target.app]
        if dragged.app.path != target.app.path {
            members.append(dragged.app)
        }

        let draggedItemIndex = dragged.container == .top ? dragged.itemIndex : nil
        removeAppInternal(targetAppID)
        removeAppInternal(draggedAppID)

        var adjustedIndex = targetItemIndex
        if let draggedItemIndex, draggedItemIndex < targetItemIndex {
            adjustedIndex -= 1
        }
        items.insert(.folder(Folder(name: "新建文件夹", apps: members)),
                     at: max(0, min(adjustedIndex, items.count)))
        persist()
    }

    /// 外部拖来的 App 放到一级某个 App 图标上 → 同样合成新文件夹
    func mergeExternalApp(_ entry: AppEntry, ontoAppID targetAppID: UUID) {
        guard let target = locate(appID: targetAppID), target.container == .top,
              let targetItemIndex = target.itemIndex else {
            // 兜底：目标不是一级 App，就直接加到一级末尾
            addApps([entry], to: .top)
            return
        }
        var members: [AppEntry] = [target.app]
        if entry.path != target.app.path {
            members.append(entry)
        }
        removeAppInternal(targetAppID)
        items.insert(.folder(Folder(name: "新建文件夹", apps: members)),
                     at: min(targetItemIndex, items.count))
        persist()
    }

    // MARK: 开机自启

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "开机自启设置失败：\(error.localizedDescription)"
            NSLog("DockDrawer launch-at-login error: \(error)")
        }
    }
}
