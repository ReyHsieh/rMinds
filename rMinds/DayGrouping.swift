import Foundation

/// 基于自定义 "每日开始时间" 的日期分组工具。
enum DayPlanner {
    static var calendar: Calendar { .current }

    /// 把任意时刻规范化为 "当天中午"，作为该日的稳定代表值。
    static func normalizedDay(_ date: Date) -> Date {
        var c = calendar.dateComponents([.year, .month, .day], from: date)
        c.hour = 12
        c.minute = 0
        c.second = 0
        return calendar.date(from: c) ?? date
    }

    /// 当前 "有效一天" 的起点：若现在已过每日开始时间则为今天该时刻，否则为昨天该时刻。
    static func currentDayStart(now: Date = Date(), hour: Int, minute: Int) -> Date {
        let midnight = calendar.startOfDay(for: now)
        let offset = hour * 60 + minute
        let candidate = calendar.date(byAdding: .minute, value: offset, to: midnight) ?? midnight
        if now >= candidate { return candidate }
        return calendar.date(byAdding: .minute, value: offset - 24 * 60, to: midnight) ?? candidate
    }

    /// 自然日偏移（0=今天，1=明天，-1=昨天），用于时间线分组与徽章；
    /// 与“每日开始时间”无关，避免刚过零点时把新记录算进“明天”。
    static func naturalDayIndex(of day: Date, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let dayStart = calendar.startOfDay(for: day)
        return calendar.dateComponents([.day], from: todayStart, to: dayStart).day ?? 0
    }

    /// 某一天相对当前有效一天的偏移天数（0=今天，1=明天，-1=昨天）。
    static func dayIndex(of day: Date, hour: Int, minute: Int, now: Date = Date()) -> Int {
        let currentBoundary = currentDayStart(now: now, hour: hour, minute: minute)
        let dayMidnight = calendar.startOfDay(for: day)
        let boundary = calendar.date(byAdding: .minute, value: hour * 60 + minute, to: dayMidnight) ?? dayMidnight
        return calendar.dateComponents([.day], from: currentBoundary, to: boundary).day ?? 0
    }

    static func headerTitle(for index: Int, day: Date) -> String {
        switch index {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return uppercaseShortDate(day)
        }
    }

    static func headerSubtitle(for index: Int, day: Date) -> String? {
        (index == 0 || index == 1) ? uppercaseShortDate(day) : nil
    }

    static func badge(for index: Int) -> String? {
        if index >= 2 { return "\(index) DAYS" }
        if index == -1 { return "YESTERDAY" }
        return nil
    }

    /// Coming up 里每一天的标签，如 "TOMORROW · 24 AUG"、"4 DAYS · 27 AUG"
    static func dayLabel(for index: Int, day: Date) -> String {
        switch index {
        case 0: return "TODAY · \(uppercaseShortDate(day))"
        case 1: return "TOMORROW · \(uppercaseShortDate(day))"
        case -1: return "YESTERDAY · \(uppercaseShortDate(day))"
        default:
            return index >= 2
                ? "\(index) DAYS · \(uppercaseShortDate(day))"
                : uppercaseShortDate(day)
        }
    }

    /// "23 AUG"
    static func uppercaseShortDate(_ date: Date) -> String {
        formatted(date, format: "d MMM")
    }

    /// "SUN"
    static func weekdayLabel(_ date: Date) -> String {
        formatted(date, format: "EEE")
    }

    /// 顶栏 "23 AUG · SUN"
    static func uppercaseHeaderDate(_ date: Date) -> String {
        formatted(date, format: "d MMM · EEE")
    }

    /// 任务行时间 "09:00"（24 小时制，与截图一致）
    static func hm(_ date: Date) -> String {
        formatted(date, format: "HH:mm")
    }

    /// 本地化日期 "8月24日 · 周日"
    static func localizedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "M月d日"
        let weekday = weekdayLabel(date)
        return "\(formatter.string(from: date)) · \(weekday)"
    }

    private static func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date).uppercased()
    }
}
