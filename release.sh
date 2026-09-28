#!/bin/bash
#
# 构建并发布 GitHub Release。
#
# 用法：
#   ./release.sh 1.0.0             # 构建 + 打包 + 创建 release（自动打 tag）
#   ./release.sh 1.0.0 --dry-run   # 只构建打包，不上传，用于本地验证产物
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
ZIP_NAME="Attention-$TAG.zip"

echo "==> 构建 $TAG"
VERSION="$VERSION" ./build.sh

echo ""
echo "==> 打包 $ZIP_NAME"
mkdir -p build
rm -f "build/$ZIP_NAME"
# --keepParent 让解压后直接得到「Attention.app」，而不是散落的 Contents/
# --norsrc 不写入 AppleDouble 的 ._ 文件：否则用 unzip（非 macOS 原生解压）
#         会把 ._CodeResources 当成真实文件放进 _CodeSignature/，导致签名校验失败
ditto -c -k --norsrc --keepParent "build/Attention.app" "build/$ZIP_NAME"
ls -lh "build/$ZIP_NAME"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  echo ""
  echo "✅ 已打包（dry-run，未上传）：build/$ZIP_NAME"
  echo "   去掉 --dry-run 即可发布到 GitHub。"
  exit 0
fi

echo ""
echo "==> 创建 GitHub Release $TAG"
gh release create "$TAG" "build/$ZIP_NAME" \
  --title "Attention $TAG" \
  --notes "$(cat <<EOF
## Attention $TAG

macOS 菜单栏待办应用，把「记住要做什么」这件事交给工具。

### 安装

1. 下载 $ZIP_NAME 并解压，得到「Attention.app」
2. 拖入「应用程序」文件夹

3. **首次打开需要右键**：在「应用程序」里右键点击「Attention」→ 选「打开」→ 在弹窗里再点一次「打开」。

   应用未经过 Apple 公证，直接双击会被 Gatekeeper 拦下。这一步只需做一次，之后正常双击即可。

   如果右键打开仍被拒绝，在终端执行：

       xattr -dr com.apple.quarantine "/Applications/Attention.app"

### 系统要求

- macOS 13 或更高版本
- Apple Silicon（M 系列芯片）

### 使用

启动后**没有 Dock 图标、也不会弹窗口**，这是正常现象。去**屏幕顶部菜单栏**点击清单图标即可打开待办面板；悬浮球默认在屏幕右上角。

### 退出

菜单栏面板里退出，或在终端执行 \`pkill Attention\`。
EOF
)"

echo ""
echo "✅ 发布完成：$(gh release view "$TAG" --json url -q .url)"
