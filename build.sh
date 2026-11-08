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
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "build/$APP_NAME.app/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP"
echo "Built: $APP"
