#!/bin/bash
# 「Dock 抽屉」构建脚本：把 Swift 源码编译成 .app
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Dock 抽屉"
EXEC="DockDrawer"
APP="build/$APP_NAME.app"

mkdir -p "build/$APP_NAME.app/Contents/MacOS" "build/$APP_NAME.app/Contents/Resources"

SDK="$(xcrun --show-sdk-path)"
echo "SDK: $SDK"
swiftc -O -sdk "$SDK" Sources/*.swift -o "build/$APP_NAME.app/Contents/MacOS/$EXEC"

cp Resources/Info.plist "build/$APP_NAME.app/Contents/Info.plist"
# 本地开发优先用作者定稿图标（含真实 App 图标，不随公开仓库分发）；
# 克隆仓库的开发者没有该文件，回退到原创公开版图标。
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "build/$APP_NAME.app/Contents/Resources/AppIcon.icns"
elif [ -f Resources/Release/AppIcon.icns ]; then
    cp Resources/Release/AppIcon.icns "build/$APP_NAME.app/Contents/Resources/AppIcon.icns"
    echo "Icon: public (Resources/Release/AppIcon.icns)"
fi

codesign --force --sign - "$APP"
echo "Built: $APP"
