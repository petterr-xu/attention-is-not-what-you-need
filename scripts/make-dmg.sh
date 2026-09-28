#!/bin/bash
#
# 把 .app 打包成带安装引导界面的 dmg。
#
# 用法：
#   ./scripts/make-dmg.sh build/Attention.app 1.0.0 build/Attention-v1.0.0.dmg
#
# 窗口布局由 AppleScript 驱动 Finder 写入 .DS_Store，因此需要「自动化」权限。
# 流程：临时可写 dmg → 挂载 → 设置图标位置与背景 → 卸载 → 压缩成只读 UDZO。
#
set -euo pipefail

APP_PATH="${1:?用法: make-dmg.sh <app路径> <版本号> <输出dmg路径>}"
VERSION="${2:?缺少版本号}"
OUT_DMG="${3:?缺少输出路径}"

VOL_NAME="Attention"
WIN_W=600
WIN_H=400
WIN_X=200
WIN_Y=200
# 图标中心坐标（内容区左上角为原点、y 向下），必须与 make-dmg-background.swift 里的
# LEFT_X / RIGHT_X / ICON_Y 保持一致，否则箭头会指不到图标。
LEFT_POS="150, 190"
RIGHT_POS="450, 190"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 转成绝对路径，后面要挂载/复制
if [ ! -d "$APP_PATH" ]; then
  echo "错误：找不到 $APP_PATH"
  exit 1
fi
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"

STAGING="$(mktemp -d)"
TMP_DMG="$(mktemp -u).dmg"
BG_DIR="$(mktemp -d)"
MOUNT_POINT="/Volumes/$VOL_NAME"

cleanup() {
  hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  rm -rf "$STAGING" "$BG_DIR" "$TMP_DMG"
}
trap cleanup EXIT

echo "==> 生成背景图"
swift "$SCRIPT_DIR/make-dmg-background.swift" "$BG_DIR" >/dev/null

echo "==> 组织安装包内容"
mkdir -p "$STAGING/.background"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "$BG_DIR/dmg-background.png" "$BG_DIR/dmg-background@2x.png" "$STAGING/.background/"

echo "==> 生成临时 dmg"
hdiutil create -srcfolder "$STAGING" -volname "$VOL_NAME" -fs HFS+ \
  -format UDRW -ov "$TMP_DMG" >/dev/null

echo "==> 挂载并设置窗口布局"
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
sleep 2

osascript <<EOF
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$WIN_X, $WIN_Y, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H + 28))}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set background picture of theViewOptions to file ".background:dmg-background.png"
    set position of item "Attention.app" of container window to {$LEFT_POS}
    set position of item "Applications" of container window to {$RIGHT_POS}
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

# 给 Finder 一点时间把布局落盘到 .DS_Store，再卸载
sync
sleep 2

echo "==> 卸载"
hdiutil detach "$MOUNT_POINT" -quiet

echo "==> 压缩为只读 dmg"
mkdir -p "$(dirname "$OUT_DMG")"
rm -f "$OUT_DMG"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" >/dev/null

echo ""
echo "✅ dmg 已生成：$OUT_DMG"
ls -lh "$OUT_DMG"
