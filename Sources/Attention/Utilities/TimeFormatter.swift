import Foundation

enum TimeFormatter {
    /// 天/月显示的上限。再长就直接摆烂——任务放到这个岁数就不是待办了。
    private static let maxDays = 29.9
    private static let maxMonths = 11.9
    /// 一个月按 30 天算
    private static let daysPerMonth = 30.0

    /// 任务时长。
    ///
    /// 一天以内用紧凑的 h/m；超过一天改用天、月。任务的生命周期可能拉到几十天
    /// （跨周自动结束可以关掉、提醒阈值也能配到天级），「960h 0m」那种写法已经没法看了。
    static func string(from interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))

        // 一天以内：保持原来的 h/m 写法
        if totalSeconds <= 86_400 {
            let hours = totalSeconds / 3600
            let minutes = totalSeconds / 60
            if hours > 0 {
                return String(format: "%dh %dm", hours, minutes % 60)
            }
            return String(format: "%dm", minutes)
        }

        // 超过一天：x.x day。下限 0.1 是格式的取值下限（按「超过 1 天才走这条路」，
        // 实际达不到），上限保证数字不会越来越长。
        let days = Double(totalSeconds) / 86_400
        if days <= maxDays {
            return String(format: "%.1f day", min(max(days, 0.1), maxDays))
        }

        let months = days / daysPerMonth
        if months <= maxMonths {
            return String(format: "%.1f month", min(max(months, 0.1), maxMonths))
        }

        return ":("
    }
}
