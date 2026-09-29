#!/bin/bash
#
# 构建并发布 GitHub Release（产物为带安装引导界面的 dmg）。
#
# 用法：
#   ./release.sh 1.0.0             # 构建 + 打包 dmg + 创建 release（自动打 tag）
#   ./release.sh 1.0.0 --dry-run   # 只构建打包，不上传，用于本地验证产物
#
# 注意：本脚本只创建 tag 和 Release，不推 main 分支。发布前请先 git push，
#       否则远程会出现「tag 指向新 commit，但 main 还停在旧 commit」的不一致。
#
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "用法: ./release.sh <版本号> [--dry-run]"
  echo "例如: ./release.sh 1.0.0"
  exit 1
fi
DRY_RUN="${2:-}"

TAG="v$VERSION"
DMG_NAME="Attention-$TAG.dmg"

echo "==> 构建 $TAG"
VERSION="$VERSION" ./build.sh

echo ""
echo "==> 打包 $DMG_NAME"
mkdir -p build
./scripts/make-dmg.sh "build/Attention.app" "$VERSION" "build/$DMG_NAME"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  echo ""
  echo "✅ 已打包（dry-run，未上传）：build/$DMG_NAME"
  echo "   去掉 --dry-run 即可发布到 GitHub。"
  exit 0
fi

echo ""
echo "==> 创建 GitHub Release $TAG"
gh release create "$TAG" "build/$DMG_NAME" \
  --title "Attention $TAG" \
  --notes "$(cat <<EOF
## Attention $TAG

macOS 菜单栏待办应用，把「记住要做什么」这件事交给工具。

### 安装

1. 下载 $DMG_NAME 并双击打开
2. 把窗口里的「Attention」拖进旁边的「Applications」文件夹
3. 如果提示「已存在同名项目」，选「替换」（升级时会出现）

4. **首次打开**：应用未经过 Apple 公证，直接双击启动会被拦下并提示「该应用未经认证」。请不要选择「移到废纸篓」，改为打开 系统设置 → 隐私与安全性，在该设置项中点击「仍要打开 Attention」，再确认一次即可。

   这一步只需做一次，之后正常双击即可。

### 系统要求

- macOS 13 或更高版本
- Apple Silicon（M 系列芯片）

### 使用

启动后**没有 Dock 图标、也不会弹窗口**，这是正常现象。去**屏幕顶部菜单栏**点击清单图标即可打开待办面板；悬浮球默认在屏幕右上角。

### 退出

鼠标右击菜单栏中的 Attention 图标并选择退出，或在终端执行 \`pkill Attention\`。
EOF
)"

echo ""
echo "✅ 发布完成：$(gh release view "$TAG" --json url -q .url)"
