# Dock 抽屉

> **普通用户**：直接去 [Releases](https://github.com/Mr-Bugman/dock-drawer/releases) 下载 `DockDrawer-1.1.dmg`，按 [安装说明](安装说明.txt) 装即可，不用看源码。
>
> **AI 协作必读**：[`AGENTS.md`](AGENTS.md) —— 架构地图、构建安装流程、12 条踩坑铁律、调试工具、定稿参数。
>
> 公开仓库含源码、文档与**原创公开版应用图标**（`Resources/Release/AppIcon.icns`）。作者本地的定稿图标（`Resources/AppIcon.icns`，含 4 个真实 App 图标）、图标源图与构建产物 `build/` 属私人资产，未随仓库分发。克隆后 `bash build.sh` 会自动使用公开版图标。

macOS 原生小工具：Dock 里常驻一个图标，点开弹出手机桌面风格的第一层面板
（**文件夹和 App 图标混排**，超过 5 个自动换行），点文件夹弹出二级网格抽屉（超 5 行内部滚动），
点 App 图标直接启动。只收 App，纯本地运行、不联网。

## 普通用户安装

**系统要求**：macOS 27 或更新版本 + Apple 芯片（M1 及以后）。
面板用的是 macOS 27 才有的系统玻璃接口，且 macOS 27 起系统本身不再支持 Intel Mac，
因此旧系统 / Intel Mac 无法运行。

1. 到 [Releases](https://github.com/Mr-Bugman/dock-drawer/releases) 下载 `DockDrawer-1.1.dmg`。
2. 打开 dmg，把「Dock 抽屉」拖进「应用程序」。
3. **首次打开**：右键点 App →「打开」→ 再点「打开」。本软件是开源自编译版本，
   没有苹果开发者签名与公证，系统会提示「无法验证开发者」，这是正常现象，只需放行一次。
4. **必须手动固定到 Dock**：本软件是后台辅助型（无菜单栏、没有普通窗口、不显示运行黑点），
   双击看起来像没反应是设计如此。打开访达 →「应用程序」→ 把「Dock 抽屉」拖到 Dock 上。
5. 点 Dock 图标弹出面板；第一次是空的，点**右上角的圆形滑杆按钮**打开整理窗口添加 App，
   或直接把访达里的 App 拖进面板。

更详细的使用方式见 [`使用说明.md`](使用说明.md)，dmg 内也附了一份 [`安装说明.txt`](安装说明.txt)。

## 构建（开发者）

```bash
bash build.sh          # 编译到 build/Dock 抽屉.app（需要 Command Line Tools）
                       # 本地有定稿图标就用它，否则自动回退到 Resources/Release/AppIcon.icns
swift Scripts/make_release_icon.swift   # 可选：重新生成原创公开版图标（不读本机名单）
# 数据层逻辑自动测试（隔离目录，不碰真实名单）
mkdir -p /tmp/testbuild && cp Scripts/store_test.swift /tmp/testbuild/main.swift
swiftc -O Sources/Store.swift /tmp/testbuild/main.swift -o /tmp/storetest
mkdir -p /tmp/ddtest && DOCKDRAWER_DATA_DIR=/tmp/ddtest /tmp/storetest
```

`Scripts/make_icon.swift` 是作者本机专用工具：它读取真实名单取前 4 个 App 图标生成**本地定稿**图标，
克隆仓库后不要运行（产物路径已被 `.gitignore` 排除，也不适合公开分发）。

## 发布打包（维护者）

```bash
bash Scripts/build_release.sh     # 独立从源码编译 + 装公开图标 + ad-hoc 签名 + 打包
                                  # 产出 build/DockDrawer-<版本>.dmg，上传为 GitHub Release 资产
```

脚本刻意不复用 `build/Dock 抽屉.app`（那份可能含本地定稿图标），而是从源码重新编译到临时目录，
只放公开图标，并附上 `安装说明.txt` 与「应用程序」快捷方式。产物为 ad-hoc 签名、未公证，
因此普通用户首次打开需右键放行，这一点已写在安装说明里。

## 结构

- `Sources/main.swift` — NSApplication 引导
- `Sources/AppDelegate.swift` — 生命周期、Dock 右键菜单、菜单栏、调试钩子
- `Sources/Store.swift` — 数据模型（`TopItem` = folder|app 混排列表）+ `~/Library/Application Support/DockDrawer/config.json` 持久化 + SMAppService 开机自启
- `Sources/PanelController.swift` — 悬浮面板（NSPanel）+ 点外收起逻辑 + 拖放解析（DropCoordinator）
- `Sources/PanelViews.swift` — 第一层混排面板 / 二级抽屉网格（与一级同一套网格）/ 第一层 App 格子；一级右上角有打开整理窗口的设置按钮
- `Sources/ManagerWindow.swift` — 整理窗口（一级 App + 各文件夹的增删改排序、拖拽、开机自启开关）

## 本机构建的三个硬约束（2026-11-08，CLT + macOS 27 SDK）

> 运行门槛：源码使用了 macOS 27 的 `NSGlassEffectView.effectIsInteractive`，
> 因此 `Info.plist` 的 `LSMinimumSystemVersion` 已设为 **27.0**；macOS 27 起系统仅支持
> Apple 芯片，编出的可执行文件为 arm64。旧系统 / Intel Mac 无法运行。

1. **不能用 `@State`**：CLT 的 SDK 里 SwiftUI 的 `@State` 走宏，但宏插件
   `libSwiftUIMacros.dylib` 缺失（只有 SwiftMacros / ObservationMacros）。
   `@Binding`、`@EnvironmentObject`、`@ObservedObject`、`@Published` 不受影响。
   所以所有状态都在三个 ObservableObject 里。
2. **不能用 `TabView(.page)`**：`PageTabViewStyle` 在 macOS 显式不可用，抽屉改用
   `ScrollView + LazyVGrid`（与一级同一套网格，超 5 行内部纵向滚动），不再做翻页。
3. **enum 关联值的自动 Codable 会带 `"_0"` 包裹**：`TopItem` 手写了 Codable，
   config.json 才是干净的 `{"folder": {...}}` / `{"app": {...}}`。

## 行为要点

- **Dock 图标 = 锁定的静态 icns**，有两套：
  - **本地定稿**（作者自用，不公开）：深灰渐变底板 calibratedWhite 0.76→0.50 + 4 个真实 App 图标 2×2，
    存 `Resources/AppIcon.icns`，由 `Scripts/make_icon.swift` 读真实名单生成。
  - **公开版**（随仓库/安装包分发）：同一套不透明底板参数，但 2×2 换成 4 个原创抽象几何符号
    （文件夹 / 点阵 / 列表 / 抽屉），不含任何第三方 App 图标，存 `Resources/Release/AppIcon.icns`，
    由 `Scripts/make_release_icon.swift` 生成，`build.sh` 与 `build_release.sh` 会自动取用。
  两者都不随名单动态重绘；要换图标直接替换对应 icns 重打包即可，**勿在代码里动态改图标**
  **不要用 `NSWorkspace.setIcon(forFile:)` 注册自定义图标**——它会和 icns 叠加显示成
  "嵌套方块"（作者踩过）；若曾被注册过，用 `setIcon(nil, forFile:)` 清除
- **icns 画稿必须完全不透明**：macOS 26+ 会给"半透明的旧式图标"垫一块玻璃底板，
  灰色从半透区域透出（作者踩过：半透磨砂底 = 灰边缘/嵌套观感；透明边距同样触发）。
  正确做法 = 不透明画稿铺满画布（磨砂观感用浅灰白渐变直接画出来）+ 系统切圆角
- **图标缓存顽固时的终极方案 = 换 bundle identifier**：CFBundleIdentifier 已从
  com.chai.dockdrawer 改为 **com.chai.dockdrawer.v2**（LS 缓存按标识索引，换标识 = 零缓存
  历史）。代价：Dock 位置需重新固定、登录项需重新开关一次；数据不受影响（按文件路径存）
- 抽屉 = **与一级同一套网格**（一行最多 5 个、66×66 格、52pt 图标、超 5 行内部纵向滚动）；
  点文件夹/‹ 返回时面板 frame 用 `NSAnimationContext` 平滑过渡 + 内容淡入（rebuildContent(animated:)）
- **拖 App 到抽屉左上角 ‹ 返回键 = 上楼**：悬停 0.6s 自动回一级（`BackButtonDropDelegate`
  里 moveApp 到 .top + `promoteToTopItem` 升级会话），落手可在一级实时重排；直接落返回键同理
- 面板图标右键菜单：打开 App / 在访达中显示 / 移除（一级和抽屉都有）
- **面板上不要气泡尾巴**：系统玻璃部件既不响应 `layer.transform` 旋转、也不响应 `layer.mask`
  裁剪（旋转/遮罩/容器融合全试过，真机均无效），作者已拍板移除所有层级的小尾巴，回归纯圆角矩形。
  若未来想要异形轮廓，只能整体换 SwiftUI Shape + Material 方案
- 编辑模式：长按 0.5s → `editMode = true`（didSet 平滑重排面板）。⊖ 徽章 = **AppKit 现画的
  NSImage**（SwiftUI 语义色离屏解析成灰，别用）+ **必须挂手势承载层的兄弟视图**
  （挂内部点击会被 onDrag/tap 吞掉，highPriorityGesture 也救不回）；晃动用 TimelineView
  （repeatForever 会把徽章出现卷进无限循环）。文件夹 ⊖ 一步直删；**面板内禁用
  confirmationDialog/弹窗**——无边框玻璃面板上按钮点不中且会被"点外收起"误伤
- 「图标下显示名称」开关存在 UserDefaults（showAppNames），改动会 refreshPanel
- 点 Dock 图标 = `applicationShouldHandleReopen` 切换面板；面板锚定在鼠标位置上方（即 Dock 图标处）
- 点外面收起 = **双保险**：mouseDown 起 0.15s 定时兜底（到点时 `NSEvent.pressedMouseButtons == 0`
  才收，键还按着=慢速点击/拖拽起点就等 mouseUp）+ mouseUp 即时收。mouseDragged 取消两者
  （拖拽不收，从访达拖 App 到面板靠这个）。**mouseUp 监听偶发收不到**（激活别窗口的点击），
  所以定时兜底不能删；也别用 drag pasteboard 判拖拽（内容残留导致之后点不收）
- 面板/抽屉背景 = `NSGlassEffectView`（Liquid Glass，macOS 26+），**作者选定 .clear 全透、无薄雾**
  （PanelController.glassStyle/glassFrost，2026-11-08 从四档预览挑的）；SwiftUI 的
  `glassEffect` 修饰器在 CLT SDK 的 swiftinterface 里不存在，别试；
  桌面对比预览：`DOCKDRAWER_GLASS_PREVIEW=1` 运行（GlassPreview.swift）
- **同一个 bundle 别在两个路径都 lsregister**：build/ 和 /Applications 同时注册时
  `open` 会把两个都拉起来、杀一个另一个还会被 LS 激活。装新版前先
  `lsregister -u` 掉 build 目录那份（或只注册 /Applications）
- **拖拽排序 = 实时让位**：面板图标拖拽走 `DragSessionTracker`（.onDrag 记会话）+
  `TopTileDropDelegate` / `DrawerCellDropDelegate`（dropEntered 里实时 moveTopItem/moveApp），
  容器挂 `.animation(spring, value: ids)` 让其他图标滑开。
  合并（拖 App 停另一 App 图标 0.7 秒）状态挂在 PanelController（mergeArm*），
  **别把状态记在 delegate 上**——delegate 随界面刷新重建。鼠标监听 mouseUp 统一 end() 会话
- DropCoordinator（closure 式拖放）仍用于：面板背景、整理窗口的格子和侧栏；拖拽会话式
  delegate 只管面板图标
- 拖 App 到一级的 App 图标上（停 0.7 秒）= 合成新文件夹（`mergeAppsIntoNewFolder` /
  `mergeExternalApp`），替掉原 App 的位置；拖到文件夹图标上 = 收进去
- 跨 Space 显示：panel collectionBehavior = canJoinAllSpaces + fullScreenAuxiliary
- 自启动判定：开机 uptime < 180s 视为登录自启，此时不自动弹面板

## 验收 / 调试

见 `使用说明.md` 文末「给以后维护的人」。
