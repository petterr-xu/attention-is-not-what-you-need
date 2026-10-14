import AppKit

/// 「任务时长提醒」的时长输入：三个框分别是天 / 小时 / 分钟。
///
/// 每个框配一个上下箭头（`NSStepper`）——可选范围与步进由这里定死，用户不用去记。
/// 同时也允许直接输入，但**边输边校验**：出错的框立刻标红，不用等到点保存。
///
/// 手工摆 frame 而不用 Auto Layout——就一行固定尺寸的控件，算好位置直接放最省心
/// （`NSStackView` 在这个项目里已经为对齐问题吃过两次亏了）。
final class DurationThresholdInputView: NSView, NSTextFieldDelegate {
    static let maxDays = 60
    static let maxHours = 24
    static let maxMinutes = 60

    private static let fieldWidth: CGFloat = 46
    private static let stepperWidth: CGFloat = 16
    private static let rowHeight: CGFloat = 22
    private static let gap: CGFloat = 3
    private static let groupGap: CGFloat = 14

    private let rows: [Row]

    /// 打开弹窗时要聚焦的那个框
    var firstField: NSTextField { rows[0].field }

    init(days: Int, hours: Int, minutes: Int) {
        let units = ["天", "小时", "分钟"]
        let limits = [Self.maxDays, Self.maxHours, Self.maxMinutes]
        let initial = [days, hours, minutes]

        var built: [Row] = []
        var x: CGFloat = 0

        for index in units.indices {
            let field = NSTextField()
            field.alignment = .right
            field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            field.stringValue = String(initial[index])
            field.frame = NSRect(x: x, y: 0, width: Self.fieldWidth, height: Self.rowHeight)

            let stepper = NSStepper()
            stepper.minValue = 0
            stepper.maxValue = Double(limits[index])
            stepper.increment = 1
            stepper.valueWraps = false
            stepper.intValue = Int32(initial[index])
            stepper.frame = NSRect(x: field.frame.maxX + Self.gap, y: 0,
                                   width: Self.stepperWidth, height: Self.rowHeight)

            let label = NSTextField(labelWithString: units[index])
            label.sizeToFit()
            label.frame.origin = NSPoint(x: stepper.frame.maxX + Self.gap,
                                         y: (Self.rowHeight - label.frame.height) / 2)

            built.append(Row(field: field, stepper: stepper, label: label, limit: limits[index]))
            x = label.frame.maxX + Self.groupGap
        }

        rows = built
        super.init(frame: NSRect(x: 0, y: 0, width: x - Self.groupGap, height: Self.rowHeight))

        for row in rows {
            row.field.delegate = self
            row.stepper.target = self
            row.stepper.action = #selector(stepperChanged(_:))
            addSubview(row.field)
            addSubview(row.stepper)
            addSubview(row.label)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    /// 三个框合计出来的总分钟数
    var totalMinutes: Int {
        rows[0].value * 1440 + rows[1].value * 60 + rows[2].value
    }

    /// 校验信息；nil 表示输入合法
    var validationError: String? {
        let names = ["天", "小时", "分钟"]
        let flags = invalidFlags
        if let bad = flags.firstIndex(of: true) {
            return "「\(names[bad])」请填 0–\(rows[bad].limit) 之间的整数"
        }
        return totalMinutes > 0 ? nil : "提醒时长不能为 0"
    }

    /// 立刻按当前内容重算，把出错的框标红。边输边校验，不等点保存。
    func refreshValidation() {
        let flags = invalidFlags
        for index in rows.indices {
            rows[index].setInvalid(flags[index])
        }
    }

    // MARK: - 输入联动

    func controlTextDidChange(_ notification: Notification) {
        // 手输了内容 → 让箭头跟上（超出范围的先钳到边界，红框交给校验去标）
        guard let edited = notification.object as? NSTextField,
              let index = rows.firstIndex(where: { $0.field === edited }) else { return }
        rows[index].stepper.intValue = Int32(min(max(rows[index].value, 0), rows[index].limit))
        refreshValidation()
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        guard let index = rows.firstIndex(where: { $0.stepper === sender }) else { return }
        rows[index].field.stringValue = String(sender.intValue)
        refreshValidation()
    }

    // MARK: - 内部

    /// 每个框是否不合法（下标 0/1/2 = 天/小时/分钟）
    private var invalidFlags: [Bool] {
        var flags = rows.map(\.isOutOfRange)
        // 全 0 时三个框都合法但整体没意义——一起标红，否则用户看不出哪里错了
        if !flags.contains(true), totalMinutes == 0 {
            flags = flags.map { _ in true }
        }
        return flags
    }

    /// 一行：输入框 + 上下箭头 + 单位标签
    private final class Row {
        let field: NSTextField
        let stepper: NSStepper
        let label: NSTextField
        let limit: Int

        init(field: NSTextField, stepper: NSStepper, label: NSTextField, limit: Int) {
            self.field = field
            self.stepper = stepper
            self.label = label
            self.limit = limit
        }

        var value: Int {
            Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }

        var isOutOfRange: Bool {
            guard let value = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return true
            }
            return value < 0 || value > limit
        }

        func setInvalid(_ invalid: Bool) {
            field.textColor = invalid ? .systemRed : .controlTextColor
            field.wantsLayer = true
            field.layer?.cornerRadius = 4
            field.layer?.borderWidth = invalid ? 1 : 0
            field.layer?.borderColor = invalid ? NSColor.systemRed.cgColor : nil
        }
    }
}
