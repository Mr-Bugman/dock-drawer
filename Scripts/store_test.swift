// Store 数据逻辑自动测试（不依赖 UI）
// 编译运行：swiftc Sources/Store.swift Scripts/store_test.swift -o /tmp/storetest
//           DOCKDRAWER_DATA_DIR=/tmp/ddtest /tmp/storetest
import Foundation

func check(_ cond: Bool, _ name: String) {
    print(cond ? "PASS  \(name)" : "FAIL  \(name)")
    if !cond { exit(1) }
}

let dataDir = ProcessInfo.processInfo.environment["DOCKDRAWER_DATA_DIR"] ?? "/tmp/ddtest"
try? FileManager.default.removeItem(atPath: dataDir)

let store = Store.shared

// 1. 默认数据
check(store.items.count == 1, "默认只有一个文件夹")
let folder1 = store.folders[0].id

// 2. 加 App：进文件夹 / 放一级
let calc = AppEntry(name: "计算器", path: "/System/Applications/Calculator.app")
let notes = AppEntry(name: "备忘录", path: "/System/Applications/Notes.app")
let chess = AppEntry(name: "国际象棋", path: "/System/Applications/Chess.app")
let maps = AppEntry(name: "地图", path: "/System/Applications/Maps.app")
store.addApps([calc, notes], to: .folder(folder1))
store.addApps([chess, maps], to: .top)
check(store.apps(in: .folder(folder1)).count == 2, "文件夹里 2 个")
check(store.topApps.map { $0.name } == ["国际象棋", "地图"], "一级顺序正确")

// 3. 移动一级 App 进文件夹指定位置
store.moveApp(appID: chess.id, to: .folder(folder1), insertIndex: 0)
check(store.apps(in: .folder(folder1)).map { $0.name } == ["国际象棋", "计算器", "备忘录"],
      "移动到文件夹第 0 位")

// 4. 移动文件夹 App 到一级末尾
store.moveApp(appID: notes.id, to: .top, insertIndex: nil)
check(store.topApps.map { $0.name } == ["地图", "备忘录"], "移到一级末尾")

// 5. 一级内排序（往前挪）
store.moveApp(appID: notes.id, to: .top, insertIndex: 0)
check(store.topApps.map { $0.name } == ["备忘录", "地图"], "一级内排序")

// 6. 手机式拼合：一级的 地图 上拖来一级的 国际象棋 → 新文件夹替换 地图 的位置
let targetItemIndexBefore = store.locate(appID: maps.id)!.itemIndex!
store.mergeAppsIntoNewFolder(targetAppID: maps.id, draggedAppID: chess.id)
check(store.folders.count == 2, "拼合后多了一个文件夹")
let merged = store.folders.last!
check(merged.apps.map { $0.name } == ["地图", "国际象棋"], "拼合成员正确")
check(!store.topApps.contains { $0.id == maps.id }, "地图不再在一级")
check(!store.apps(in: .folder(folder1)).contains { $0.id == chess.id }, "国际象棋不再在原文件夹")
if case .folder(let f) = store.items[targetItemIndexBefore] {
    check(f.id == merged.id, "新文件夹替换单标位置")
} else {
    check(false, "新文件夹替换单标位置")
}

// 7. 同路径去重
let dup = AppEntry(name: "地图", path: "/System/Applications/Maps.app")
store.addApps([dup], to: .folder(merged.id))
check(store.apps(in: .folder(merged.id)).count == 2, "同路径去重")

// 8. 外部拖来的 App 放到一级 App 上 → 也合成新文件夹
let clock = AppEntry(name: "时钟", path: "/System/Applications/Clock.app")
store.addApps([clock], to: .top)
let clockID = clock.id
let clockItemIndex = store.locate(appID: clockID)!.itemIndex!
store.mergeExternalApp(AppEntry(name: "图库", path: "/System/Applications/Freeform.app"),
                       ontoAppID: clockID)
check(store.folders.count == 3, "外部拼合产生新文件夹")
check(!store.topApps.contains { $0.id == clockID }, "原一级 App 被收进文件夹")
if case .folder(let f) = store.items[clockItemIndex] {
    check(f.apps.map { $0.name } == ["时钟", "图库"], "外部拼合位置正确")
} else {
    check(false, "外部拼合位置正确")
}

// 9. 删除文件夹
store.deleteFolder(store.folders[0].id)
check(store.folders.count == 2, "删除文件夹")

// 9.5 第一层内拖拽排序（文件夹和 App 混排挪位）
let orderBefore = store.items.map { $0.id }
let movedID = orderBefore[2]
store.moveTopItem(itemID: movedID, toIndex: 0)
check(store.items.map { $0.id }.first == movedID, "一级条目挪到第 0 位")
var expectedOrder = orderBefore
expectedOrder.remove(at: 2)
expectedOrder.insert(movedID, at: 0)
check(store.items.map { $0.id } == expectedOrder, "其余条目顺序保持")
store.moveTopItem(itemID: movedID, toIndex: 0) // 挪回自己原地 = 无操作
check(store.items.map { $0.id } == expectedOrder, "挪到原位不炸")

// 10. 落盘可读回
let file = URL(fileURLWithPath: dataDir).appendingPathComponent("config.json")
let decoded = try JSONDecoder().decode([TopItem].self, from: Data(contentsOf: file))
check(decoded.count == store.items.count, "落盘后可读回，条数一致")

print("ALL TESTS PASSED")
