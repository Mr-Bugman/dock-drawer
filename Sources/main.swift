import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 不再强制 .regular：配合 Info.plist 的 LSUIElement（辅助型形态），
// 运行黑点消失；Dock 图标靠用户手动固定（拖入一次即可）
app.run()
