import Foundation
import SwiftData

/// 一条记录：碎碎念文字 / 待办 / 照片 / 语音。
/// 一切皆记录，按时间倒序汇成时间线；标签从正文的 #话题 解析。
@Model
final class Record {
    var id: UUID
    var text: String = ""
    var kindRaw: String = Record.Kind.text.rawValue
    var createdAt: Date

    // 待办
    var isDone: Bool = false
    var dueDay: Date? = nil
    var dueTime: Date? = nil
    var wantsReminder: Bool = false

    // 标记
    var isPinned: Bool = false
    var isHighlighted: Bool = false

    // 媒体
    var photoData: Data? = nil
    var voiceFileName: String? = nil
    var voiceDuration: Double = 0

    init(
        id: UUID = UUID(),
        text: String = "",
        kind: Kind = .text,
        createdAt: Date = Date(),
        isDone: Bool = false,
        dueDay: Date? = nil,
        dueTime: Date? = nil,
        wantsReminder: Bool = false,
        isPinned: Bool = false,
        isHighlighted: Bool = false,
        photoData: Data? = nil,
        voiceFileName: String? = nil,
        voiceDuration: Double = 0
    ) {
        self.id = id
        self.text = text
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.isDone = isDone
        self.dueDay = dueDay
        self.dueTime = dueTime
        self.wantsReminder = wantsReminder
        self.isPinned = isPinned
        self.isHighlighted = isHighlighted
        self.photoData = photoData
        self.voiceFileName = voiceFileName
        self.voiceDuration = voiceDuration
    }
}

extension Record {
    enum Kind: String {
        case text
        case todo
        case photo
        case voice
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    /// 是否待办（唯一有“状态”的记录类型）
    var isTodo: Bool { kind == .todo }
}

/// 旧 rDos 任务 → 新 Record 的一次性迁移。
enum TaskMigrator {
    private static let flagKey = "migrated.taskItems.v1"

    static func migrateIfNeeded(context: ModelContext) {
        let defaults = SharedStore.userDefaults
        guard !defaults.bool(forKey: flagKey) else { return }
        defer { defaults.set(true, forKey: flagKey) }

        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        guard !tasks.isEmpty else { return }

        for task in tasks {
            guard !task.isArchived else {
                context.delete(task)
                continue
            }
            let record = Record(
                text: task.title,
                kind: .todo,
                createdAt: task.createdAt,
                isDone: task.isCompleted,
                dueDay: task.day,
                dueTime: task.time,
                wantsReminder: task.wantsReminder,
                photoData: nil,
                voiceFileName: nil,
                voiceDuration: 0
            )
            context.insert(record)
            context.delete(task)
        }
        try? context.save()
    }
}
