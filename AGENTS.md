# AGENTS.md — Dock 抽屉 · AI 协作开发指南

> 本文档面向参与开发的 AI 助手。改动前必读；违反"铁律"章节的教训都来自真实踩坑。

## 一、项目是什么

**Dock 抽屉**：macOS 原生工具（Swift + AppKit/SwiftUI，无第三方依赖，无 Xcode 工程文件）。
Dock 常驻一个图标（当前为辅助型形态 LSUIElement，无运行黑点，需手动从访达拖入 Dock 固定）→
点击弹出现代玻璃质感面板 → **一级页面**：文件夹磁贴与直接摆放的 App 图标混排 →
点文件夹弹**二级网格抽屉**（与一级同一套网格样式）→ 点 App 图标启动。

- 目标用户：开发者本人（作者），中文界面
- 数据：`~/Library/Application Support/DockDrawer/config.json`（TopItem 混排格式，手写 Codable）
- 运行身份：`com.chai.dockdrawer.v2`（v1 缓存顽固，已弃用，**不要再改回**）
- 安装位置：`/Applications/Dock 抽屉.app`

## 二、构建 / 安装 / 测试

```bash
bash build.sh                    # 编译到 build/Dock 抽屉.app（CLT swiftc，无需 Xcode）
swift Scripts/make_icon.swift    # 重新生成应用图标 icns（读真实名单取图标）
swift /tmp/xxx.swift             # 逻辑测试见 README"测试"节
```

安装（**必须按此顺序**，见铁律 R1）：
```bash
killall DockDrawer 2>/dev/null; sleep 1
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -u "build/Dock 抽屉.app" 2>/dev/null          # 先注销旧路径
rm -rf "/Applications/Dock 抽屉.app"
cp -R "build/Dock 抽屉.app" /Applications/
/System/Library/Frameworks/CoreServices.framework/.../lsregister -f "/Applications/Dock 抽屉.app"
killall Dock                                     # 强制刷新图标缓存
open "/Applications/Dock 抽屉.app"
```

逻辑测试（不依赖 UI）：
```bash
cp Scripts/store_test.swift /tmp/testbuild/main.swift
swiftc -O Sources/Store.swift /tmp/testbuild/main.swift -o /tmp/storetest
DOCKDRAWER_DATA_DIR=/tmp/ddtest /tmp/storetest    # 20 项断言
```

## 三、架构与文件地图

- `Sources/main.swift` — NSApplication 引导（**不得恢复 setActivationPolicy(.regular)**，见 R6）
- `Sources/AppDelegate.swift` — 生命周期、Dock 右键菜单、外部点击监听（收起判定）、调试开关入口 `debugValue`
- `Sources/Store.swift` — 数据模型（TopItem 混排）+ JSON 持久化（**0.35s 防抖**）+ showAppNames 设置
- `Sources/PanelController.swift` — 面板窗口/定位/外部点击收起判定/拖拽会话 DragSessionTracker/三个 DropDelegate/BackButtonDropDelegate
- `Sources/PanelViews.swift` — TopStripView（一级混排）/DrawerView（二级网格）/FolderIconView/AppTileView/DrawerAppIcon/RemoveBadge/WiggleEffect
- `Sources/ManagerWindow.swift` — 整理窗口（侧栏 + 详情网格 + 设置）
- `Sources/AppIconFactory.swift` — **已废弃但保留**（动态图标机制被作者否决，勿重新启用或调用）
- `Sources/GlassPreview.swift` — 图标/气泡候选预览渲染器（调试用）
- `Scripts/make_icon.swift` — 生成 icns（读真实名单前 4 个 App；**作者已定稿深灰渐变底板 0.76→0.50 + 2×2 真实图标**）
- `Scripts/store_test.swift` — Store 逻辑测试

## 四、铁律（每条都踩过坑，违反 = 回炉）

### R1. 双路径注册陷阱
同一 bundle 在 build/ 与 /Applications 同时 lsregister 会互相复活（kill 一个另一个被 LS 重拉）。
重装必须先 `lsregister -u` 旧路径，再 rm → cp → lsregister -f 新路径 → killall Dock。

### R2. 图标画稿必须完全不透明（alpha=1.0 铺满画布）
macOS 26+ 给半透明图标垫玻璃底板：灰边、嵌套观感全因它。旋转(frameRotation 会崩)/layer.transform/
layer.mask/容器融合/换 bundle 标识/清缓存**全部无效**——系统在合成器层面垫板。
作者最终定稿：**不透明深灰渐变底板（0.76→0.50）铺满画布 + 4 个真实 App 图标 2×2**。
"半透磨砂"与"干净边缘"在静态 icns 里二选一，作者选了后者。

### R3. 禁止 NSWorkspace.setIcon(forFile: bundlePath)
自定义图标会和 icns 叠加显示成嵌套方块。若曾注册过：`setIcon(nil, forFile:)` 清除 +
清三处 iconservices 缓存（~/Library/Caches/com.apple.iconservices.store、
/var/folders/*/C|T/com.apple.iconservices*）+ killall Dock。

### R4. 落盘 / 图标回写必须防抖
拖拽实时让位时每格触发 moveApp——同步写盘 + iconutil 重写 icns（含进程调用）会让拖拽卡顿。
- Store.persist：0.35s 防抖，flushPersist() 在拖拽结束/收面板/退出时冲刷
- AppIconFactory icns 回写：1.2s 防抖（该机制已随动态图标废弃，如恢复须保留防抖）

### R5. 面板内禁用 confirmationDialog / NSAlert / 任何弹窗
无边框玻璃面板上弹窗按钮点不中（卡死），且会被"点外收起"误伤。
确认类交互一律面板内完成（如文件夹 ⊖ 一步直删——两段式确认被作者否决）。

### R6. LSUIElement（辅助型形态）与 main.swift
Info.plist `LSUIElement=true`（无运行黑点）+ main.swift **不得 setActivationPolicy(.regular)**
（运行时设置会覆盖 plist 声明，黑点回归——踩过）。辅助型无菜单栏、不自动进 Dock；
点击已固定的 Dock 图标可正常触发 reopen 弹面板（已实测）。

### R7. 编辑模式 ⊖ 徽章三要素
1. 徽章 = **AppKit 现画 NSImage**（SwiftUI 语义色离屏解析成灰）
2. 必须是**手势承载层的兄弟视图**（挂内部点击被 onDrag/tap 吞掉，highPriorityGesture 也救不回）
3. 晃动用 **TimelineView(.animation)**（repeatForever 会把徽章出现卷进无限循环 → 永远半透明）
移除/结构变化包 withAnimation + transition 才有动画。

### R8. 收起判定 = "松开即收，持续按住不收"
mouseDown 起 0.15s 定时：到点时 `NSEvent.pressedMouseButtons == 0` 才收；
mouseUp 送达即收。**不看移动距离**（微动也算点击——距离判定被作者否决）。
mouseUp 送达不可靠（激活别窗口的点击会丢），定时兜底不能删。
真拖拽的 mouseUp 被拖拽会话吞掉 → 面板保留（拖 App 进面板靠这个）。

### R9. delegate 不能存可变状态
DropDelegate/WiggleEffect 等随界面刷新重建，可变状态一律挂
DragSessionTracker / PanelController 单例。

### R10. Store 不得反向依赖界面层
Store → 界面的通知走 `dockDrawerPrefChanged`（设置变更）。
否则 store_test 编译不过（测试只编译 Store.swift）。

### R11. SwiftUI 语义色在离屏渲染里解析不可靠
Color.red 等在 cacheDisplay 下变灰。需要精确颜色的 UI（徽章等）用 AppKit NSImage 现画。

### R12. 调试开关走 defaults 域 = bundle 标识
`defaults write com.chai.dockdrawer.v2 <KEY> <value>`（**注意 v2 后缀**，旧域无效——踩过）。
读取统一走 `AppDelegate.debugValue()`（环境变量优先，defaults 兜底）。
直接 exec 带环境变量会被 LaunchServices 重拉丢失；launchctl setenv 也够不着 GUI 会话。

## 五、调试工具

| defaults 键（域 com.chai.dockdrawer.v2） | 值 | 作用 |
|---|---|---|
| DOCKDRAWER_SNAPSHOT | panel / drawer / drawer-empty / drawer-edit / panel-edit / manager / appicon | 渲染对应界面为 PNG 后退出 |
| DOCKDRAWER_SNAPSHOT_OUT | PNG 路径 | 输出位置 |
| DOCKDRAWER_ICON_PREVIEW | 目录 | 图标候选 512px 渲染 |
| DOCKDRAWER_ICON_DOCKSIZE | 目录 | 图标候选按 Dock 真实尺寸(64pt)渲染放大 |
| DOCKDRAWER_BUBBLE_SNAPSHOT_ONLY | 目录 | 气泡形状候选渲染（历史） |
| DOCKDRAWER_DEBUG_MANAGER | 1 | 启动即开整理窗口 |
| DOCKDRAWER_DEBUG_DRAWER | 文件夹名 / first | 启动直接进抽屉 |
| DOCKDRAWER_DATA_DIR | 目录 | 数据目录重定向（测试隔离） |

配套脚本：`/tmp/` 下有像素取样、icns 尺寸检查等 swift 小工具（见聊天记录）。
玻璃效果离屏渲染不出图（cacheDisplay 和 layer.render 都不行）——玻璃/形状类改动只能真机看或像素取样。

## 六、视觉定稿参数（作者逐轮确认）

- 面板：无尾巴（所有层级），NSGlassEffectView `.clear` + 白雾 0.25，圆角 20
- 一级/二级网格：一行最多 5 个、66×66 格、间距 10；抽屉超 5 行内部纵向滚动
- 文件夹磁贴：可见 52×52（灰 10% 底、圆角 13、minis 13pt），点击区 66×66
- App 图标格：52pt 图标悬浮于 66×66 格
- 应用图标：深灰渐变底板（0.76→0.50）铺满画布 + 名单前 4 个真实 App 图标 2×2（tile 360、gap 28、bgInset 60）
- 高光描边（白 0.9，宽 6）提亮边缘；无深色描边
- 图标名：Dock 抽屉；bundle：com.chai.dockdrawer.v2

## 七、已知边界 / 未做

- 启动台拖不出 App（系统限制，已向作者说明）
- 不收文件/文件夹/网址（只收 App）
- 不签名公证（自己用；首次打开右键 → 打开放行）
- 图标静态：名单变化不刷新 Dock 图标（重跑 make_icon.swift + 重打包可刷新）
- 抽屉内多级子文件夹：未做

## 八、协作流程约定

- 改动后必须：`bash build.sh` 零错误 → 快照/真机验证 → 按第二节安装 → 让作者验收
- 验收以作者的 Dock 实际观感为准；离屏快照仅验证内容结构，玻璃/透明效果不可见
- 每次踩新坑：更新本文件铁律章节 + 外部记忆文件
