# Attention Is Not What You Need

> 一款 Mac 端轻量化待办管理应用：帮你在多任务并行时，把「注意力」从「记住要做什么」上解放出来。

名字向 [《Attention Is All You Need》](https://arxiv.org/abs/1706.03762)（Transformer 的开山之作）致意，但反其道而行——**注意力不是你所需要的东西**。频繁在任务间切换会打散注意力，你不该靠脑力去记住「当前在做什么、接下来还有什么」。把这件事交给工具，你只需专注当下。

## 它解决什么问题

日常办公总会遇到多任务并行：改需求、回消息、开会……频繁切换让你忘记「现在在做什么、待会要做什么」。

这个应用像一本记事本，记录你手头有哪些任务；切换时打开它，一眼看清：

- 现在在做什么、已经做了多久
- 还有什么没做、各自挂了多久

## 功能

- **待办列表**：手动添加 / 结束 / 删除任务，支持重命名，删除前二次确认
- **当前任务**：点击选中为「当前在做」，开始计时并置顶；再次点击取消选中
- **计时**（分钟粒度，避免分散注意力）：
  - 当前任务显示本次会话投入时长（单次会话，切走归零）
  - 挂起任务显示挂起时长
- **排序**：当前任务永远第一，其余按挂起时长越久越靠前
- **已完成列表**：结束的任务进入独立列表，默认展示当天结束的，可一键放回
- **自动结束**：创建于上一个自然周（或更早）的任务，跨周后自动结束（启动时 + 常驻每分钟检查），可手动加回
- **数据持久化**：待办 + 已完成列表存本地 JSON，重启保留；计时状态重启清零

## 形态

- **菜单栏图标**：点击顶部菜单栏的清单图标，弹出待办面板
- **悬浮窗**：默认在屏幕右上角，可折叠成圆形浮标、可拖动；菜单栏面板底部「显示悬浮窗」开关控制显隐

## 下载安装

到 [Releases](https://github.com/petterr-xu/attention-is-not-what-you-need/releases) 下载最新的 `Attention-vX.Y.Z.zip`：

1. 解压得到「Attention.app」，拖入「应用程序」文件夹
2. **首次打开需要右键**：在「应用程序」里右键点击「Attention」→ 选「打开」→ 弹窗里再点一次「打开」

应用未经 Apple 公证（个人开发者分发需要每年 $99 的开发者账号），直接双击会被 Gatekeeper 拦下。上述操作只需做一次，之后正常双击即可。

如果右键打开仍被拒绝，在终端执行：

```bash
xattr -dr com.apple.quarantine "/Applications/Attention.app"
```

**系统要求**：macOS 13+、Apple Silicon（M 系列芯片）。

## 构建（开发者）

依赖：macOS 13+、Swift 工具链（无需完整 Xcode）。

```bash
./build.sh
```

产物在 `build/Attention.app`，拖入「应用程序」后双击运行，或 `open "build/Attention.app"`。

## 发布新版本

```bash
./release.sh 1.0.1            # 构建 + 打包 + 创建 GitHub Release
./release.sh 1.0.1 --dry-run  # 只打包不上传，用于本地验证产物
```

脚本会自动编译、打包成 `build/Attention-vX.Y.Z.zip`、打 tag，并通过 `gh` 创建 Release（release notes 内含 Gatekeeper 绕过说明）。

版本号也可单独传给 `build.sh`：`VERSION=1.0.1 ./build.sh`。

## 图标

图标由 `scripts/make-icon.swift` 用 CoreGraphics 矢量绘制生成——靛蓝→紫渐变底 + 三条清单行，第一行高亮代表「当前任务」，对应应用里「当前任务置顶」的核心交互。改设计后重新生成：

```bash
swift scripts/make-icon.swift /tmp/AppIcon.iconset
iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
```

## 使用

- **菜单栏**：点击清单图标 → 待办面板
- **添加任务**：输入框输入后回车
- **切换当前任务**：点击任务行
- **结束**：任务右侧 ✓；**放回**：已完成列表的 ↩；**删除**：🗑（有确认）；**重命名**：✎（原地编辑，回车保存）
- **悬浮窗**：右上角圆形浮标，点击展开、拖动移动

## 数据位置

`~/Library/Application Support/Attention/tasks.json`

## 技术说明

- Swift/SwiftUI 原生，Swift Package Manager 构建（`swift build`），不依赖 `.xcodeproj`
- 菜单栏：`MenuBarExtra`（`.window` 样式）
- 悬浮窗：`NSPanel`（无边框、`.floating`）+ `NSVisualEffectView` 毛玻璃
- 计时：存储时间点 + 定时刷新算差值，保证准确

## 常见问题

- **看不到菜单栏图标**：请以 `.app` 方式运行（`open` 打开），纯命令行 `swift run` 不显示菜单栏图标。
- **退出应用**：`pkill Attention`（菜单栏应用无 Dock 图标）。
