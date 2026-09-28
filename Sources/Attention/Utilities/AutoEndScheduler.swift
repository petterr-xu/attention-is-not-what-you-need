import Foundation

enum AutoEndScheduler {
    /// 本周一 00:00（自然周起点）
    static func startOfCurrentWeek(from date: Date = Date(),
                                   calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// 判断任务是否「属于上一自然周（或更早）」，即创建时间早于本周起点
    static func isStale(_ task: TodoTask,
                        now: Date = Date(),
                        calendar: Calendar = .current) -> Bool {
        task.createdAt < startOfCurrentWeek(from: now, calendar: calendar)
    }
}
