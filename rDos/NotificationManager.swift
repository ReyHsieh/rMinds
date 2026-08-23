import Foundation
import UserNotifications

/// 本地提醒通知。
enum NotificationManager {
    static func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    static func schedule(_ task: TaskItem) {
        guard let time = task.time, time > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = "任务时间到了"
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(_ task: TaskItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// 以当前任务全量刷新待发通知。
    static func refreshPending(tasks: [TaskItem], enabled: Bool) {
        cancelAll()
        guard enabled else { return }
        for task in tasks where !task.isCompleted && task.wantsReminder {
            schedule(task)
        }
    }

    /// 请求权限并调度；未授权时回调 false（由调用方决定是否回退开关）。
    static func requestAndSchedule(_ task: TaskItem, onResult: ((Bool) -> Void)? = nil) {
        requestAuthorization { granted in
            if granted {
                schedule(task)
            } else {
                cancel(task)
            }
            onResult?(granted)
        }
    }
}
