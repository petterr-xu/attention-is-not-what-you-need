import AppKit

/// 「配置 MCP 客户端」弹窗的正文。
///
/// 用带边框的等宽代码框，把「可以直接复制的片段」和说明文案在视觉上分开——
/// 混在一整段纯文本里很难读。路径不单独展示，它本来就含在 Claude Code 那条命令里。
///
/// 两个刻意的实现选择：
/// 1. **手工摆 frame 而不用 Auto Layout**。内容就是固定的几块，`NSStackView` 在这里反而要跟
///    一堆固有尺寸与对齐规则较劲（试过，它的 `.width` 对齐并不会拉伸短标签，文案会跑到右边）。
/// 2. **文案和代码都用 `NSTextView`，高度用 layout manager 量**。`NSTextField` 对「没有换行符
///    也没有空格的长文本」（比如带长路径的命令）不会在框宽内折行，会直接横向溢出被裁掉；
///    而 `boundingRect` 量出来的行数又可能和实际渲染对不上。用渲染它的同一套引擎量高度才准。
enum MCPConfigAccessoryView {
    /// 正文内容宽度
    static let width: CGFloat = 480

    private static let captionFont = NSFont.systemFont(ofSize: 11)
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let boxPaddingX: CGFloat = 10
    private static let boxPaddingY: CGFloat = 8
    private static let captionToContent: CGFloat = 6
    private static let betweenBlocks: CGFloat = 16

    /// helper 出问题时的提示。只有真出问题才不为 nil，正常路径下弹窗不含任何噪音。
    struct Warning {
        let message: String
        /// 需要用户执行的修复命令，会以代码框展示
        let fixCommand: String?
    }

    static func make(json: String, command: String, warning: Warning?) -> NSView {
        var blocks: [(view: NSView, spacingAfter: CGFloat)] = []

        for (caption, code) in [("通用配置（Claude Desktop / Cursor 等）", json),
                                ("Claude Code 一条命令（user 作用域 = 所有项目可用）", command)] {
            blocks.append((captionLabel(caption), captionToContent))
            blocks.append((codeBox(code), betweenBlocks))
        }

        if let warning {
            blocks.append((captionLabel(warning.message, color: .systemOrange),
                           warning.fixCommand == nil ? 0 : captionToContent))
            if let fixCommand = warning.fixCommand {
                blocks.append((codeBox(fixCommand), 0))
            }
        }

        // 最后一块之后不留白，高度才算得准
        blocks[blocks.count - 1].spacingAfter = 0

        let container = FlippedContainerView()
        var cursor: CGFloat = 0
        for block in blocks {
            block.view.frame.origin = NSPoint(x: 0, y: cursor)
            container.addSubview(block.view)
            cursor += block.view.frame.height + block.spacingAfter
        }
        container.frame = NSRect(x: 0, y: 0, width: width, height: cursor)
        return container
    }

    // MARK: - 组成块

    private static func captionLabel(_ text: String, color: NSColor = .secondaryLabelColor) -> NSTextView {
        textBlock(text,
                  attributes: textAttributes(font: captionFont, color: color, lineBreakMode: .byWordWrapping),
                  width: width,
                  selectable: false)
    }

    private static func codeBox(_ code: String) -> NSView {
        let innerWidth = width - boxPaddingX * 2
        let content = textBlock(code,
                                attributes: textAttributes(font: codeFont,
                                                           color: .labelColor,
                                                           lineBreakMode: .byCharWrapping),
                                width: innerWidth,
                                selectable: true)

        let box = NSView(frame: NSRect(x: 0, y: 0,
                                       width: width,
                                       height: content.frame.height + boxPaddingY * 2))
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        content.frame.origin = NSPoint(x: boxPaddingX, y: boxPaddingY)
        box.addSubview(content)
        return box
    }

    // MARK: - 共用

    private static func textAttributes(font: NSFont,
                                       color: NSColor,
                                       lineBreakMode: NSLineBreakMode) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineBreakMode
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    /// 按固定宽度排版一段文本，高度由 layout manager 实测
    private static func textBlock(_ text: String,
                                  attributes: [NSAttributedString.Key: Any],
                                  width: CGFloat,
                                  selectable: Bool) -> NSTextView {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        view.isEditable = false
        view.isSelectable = selectable
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))

        // 把容器宽度钉死再量：直接用容器的宽度排版，量出来的行数就是实际渲染的行数
        if let container = view.textContainer, let layout = view.layoutManager {
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            layout.ensureLayout(for: container)
            view.frame.size.height = ceil(layout.usedRect(for: container).height)
        }
        return view
    }
}

/// 翻转坐标系的容器：y=0 在顶部，便于自上而下顺序摆放子视图
private final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}
