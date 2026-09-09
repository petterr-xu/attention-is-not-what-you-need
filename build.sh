#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="待办"
EXECUTABLE="TodoMenu"
BUNDLE_ID="com.xuwenduan.todomenu"
VERSION="1.0.0"

echo "==> 编译 release 版本..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$EXECUTABLE"

APP_DIR="build/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> 代码签名（本地自签）..."
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "✅ 打包完成：$APP_DIR"
echo "   可拖入「应用程序」目录后双击运行，或直接执行："
echo "   open \"$APP_DIR\""
