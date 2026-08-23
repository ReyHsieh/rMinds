import Foundation
import SwiftData

/// App 与小组件扩展共享的 App Group（数据库与设置都放在组容器里）。
enum SharedStore {
    static let appGroupId = "group.com.reyhsiehchang.rDos"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    static var storeURL: URL? {
        containerURL?.appendingPathComponent("rDos.store")
    }

    static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }
}

/// 一个待办任务。
/// `day` 为该任务所属的自然日（统一规范化到当天中午，避免时区/夏令时边界问题），
/// 为 nil 时表示 "Someday"（某天再说）；`time` 是具体到分的时间点，nil 表示无时间。
/// `bodyText` 为正文（详情展开时显示）；`isArchived` 支持左滑手动归档。
@Model
final class TaskItem {
    var id: UUID
    var title: String
    var bodyText: String = ""
    var day: Date?
    var time: Date?
    var wantsReminder: Bool
    var isCompleted: Bool
    var completedAt: Date?
    var isArchived: Bool = false
    var archivedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        bodyText: String = "",
        day: Date? = nil,
        time: Date? = nil,
        wantsReminder: Bool = false,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.bodyText = bodyText
        self.day = day
        self.time = time
        self.wantsReminder = wantsReminder
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
    }
}
