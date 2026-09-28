import Foundation

enum TimeFormatter {
    /// 将时长格式化为分钟单位：< 1 小时显示「Xm」，≥ 1 小时显示「Xh Ym」
    static func string(from interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3600
        let minutes = totalSeconds / 60
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes % 60)
        }
        return String(format: "%dm", minutes)
    }
}
