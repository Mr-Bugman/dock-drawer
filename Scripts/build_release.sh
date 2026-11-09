#!/bin/bash
# 构建「公开分发版」dmg：从源码独立编译 → 装原创公开图标 → ad-hoc 签名 → 打包。
# 刻意不复用 build/Dock 抽屉.app：那份含本地定稿图标（真实 App 图标 2×2），不可公开分发。
# 产物：build/DockDrawer-<版本>.dmg（build/ 已被 .gitignore 排除，不进仓库）。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Dock 抽屉"
EXEC="DockDrawer"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
PUBLIC_ICON="Resources/Release/AppIcon.icns"
README_TXT="安装说明.txt"
DMG="build/DockDrawer-${VERSION}.dmg"
STAGE="$(mktemp -d /tmp/dockdrawer-release.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> 版本 $VERSION / 临时目录 $STAGE"

# 1. 公开图标（原创抽象几何，不读本机名单、不含第三方 App 图标）
if [ ! -f "$PUBLIC_ICON" ]; then
    echo "==> 生成公开图标"
    swift Scripts/make_release_icon.swift
fi
[ -f "$README_TXT" ] || { echo "缺少 $README_TXT" >&2; exit 1; }

# 2. 从源码独立编译到 staging，避免把本地定稿资产带进安装包
SDK="$(xcrun --show-sdk-path)"
APP="$STAGE/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
echo "==> 编译（$(basename "$SDK")）"
swiftc -O -sdk "$SDK" Sources/*.swift -o "$APP/Contents/MacOS/$EXEC"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$PUBLIC_ICON" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

# 3. dmg 内容：App + 应用程序快捷方式 + 中文安装说明
ln -s /Applications "$STAGE/Applications"
cp "$README_TXT" "$STAGE/$README_TXT"

echo "==> 打包 dmg"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null

echo "==> 校验"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature' || true
lipo -info "$APP/Contents/MacOS/$EXEC"
shasum -a 256 "$DMG"
ls -lh "$DMG"
echo "Done: $DMG"
