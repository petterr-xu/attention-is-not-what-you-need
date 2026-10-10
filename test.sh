#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# 本机默认工具链是 Command Line Tools。CLT 自带 swift-testing 的 Testing.framework，
# 但缺少 SwiftPM 需要的模块搜索路径与 lib_TestingInterop.dylib，直接 swift test 会链接/运行失败。
# 完整 Xcode 的工具链是自洽的，用 DEVELOPER_DIR 指向它即可：
# 无需 sudo 改 xcode-select，也不影响 ./build.sh 用 CLT 打包（构建 App 不需要 Xcode）。
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [ ! -d "$DEVELOPER_DIR" ]; then
    echo "❌ 未找到 Xcode：$DEVELOPER_DIR"
    echo "   跑测试需要完整 Xcode（仅构建/打包 App 不需要）。"
    echo "   若 Xcode 装在别处：DEVELOPER_DIR=<路径> ./test.sh"
    exit 1
fi

export DEVELOPER_DIR
echo "==> swift test（DEVELOPER_DIR=${DEVELOPER_DIR}）"
swift test "$@"
