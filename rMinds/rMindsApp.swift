import SwiftUI
import SwiftData
import WidgetKit
import UIKit

/// 外观应用器：走 UIWindow 级 override。
/// 不用 SwiftUI 的 preferredColorScheme——它从明确值切回 nil（跟随系统）时不会重解析，
/// 而强制重建视图又会拆掉正在展示的 sheet。
enum AppearanceApplier {
    static func apply(_ mode: AppearanceMode) {
        let style: UIUserInterfaceStyle
        switch mode {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
    }
}

@main
struct rDosApp: App {
    @State private var settings = AppSettings.shared

    let container: ModelContainer

    init() {
        do {
            // TaskItem 仅用于读取旧 rDos 数据并迁移到 Record
            let schema = Schema([Record.self, TaskItem.self])
            let configuration = SharedStore.storeURL.map { ModelConfiguration(schema: schema, url: $0) }
            if let configuration {
                container = try ModelContainer(for: schema, configurations: [configuration])
            } else {
                container = try ModelContainer(for: schema)
            }
            // 旧 rDos 任务一次性迁移为记录
            TaskMigrator.migrateIfNeeded(context: ModelContext(container))
        } catch {
            fatalError("无法创建本地数据库: \(error)")
        }
        #if DEBUG
        SeedData.seedIfNeeded(container: container)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(settings)
                .onAppear { AppearanceApplier.apply(settings.appearance) }
                .onChange(of: settings.appearance) { _, newValue in
                    AppearanceApplier.apply(newValue)
                }
        }
        .modelContainer(container)
    }
}

// MARK: - 调试构建专用示例数据

#if DEBUG
/// 对照设计截图的示例数据。Release 构建不包含，不会预置任何数据。
enum SeedData {
    private static let seedKey = "didSeedSampleTasks"

    /// 仅安装后第一次启动时预置，用于 UI 对比。
    static func seedIfNeeded(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: seedKey) else { return }
        let context = ModelContext(container)
        insertSamples(into: context)
        try? context.save()
        UserDefaults.standard.set(true, forKey: seedKey)
    }

    static func loadSample(context: ModelContext) {
        deleteAll(context)
        insertSamples(into: context)
        try? context.save()
    }

    static func reset(_ context: ModelContext) {
        deleteAll(context)
        UserDefaults.standard.set(false, forKey: seedKey)
        try? context.save()
    }

    private static func deleteAll(_ context: ModelContext) {
        try? context.delete(model: TaskItem.self)
    }

    /// (文字, 类型, 分钟前, 待办相关: 是否完成/天偏移/时/分)
    private static let samples: [(String, Record.Kind, Int, Bool, Int?, Int?, Int?, Bool, Bool)] = [
        ("早上骑车的时候想到：碎碎念也许不需要被管理，被记住就够了", .text, 26, false, nil, nil, nil, true, false),
        ("整理本周的产品草图", .todo, 240, false, 0, 9, 0, false, false),
        ("确认 rMinds 的中文文案", .todo, 300, true, nil, nil, nil, false, false),
        ("给植物浇水", .todo, 390, true, nil, nil, nil, false, false),
        ("读《禅与摩托车维修艺术》第 3 章", .todo, 1500, false, 0, 21, 30, false, false),
        ("突然觉得“记录”和“管理”是两件事，做产品时别混", .text, 1900, false, nil, nil, nil, false, true),
        ("买牛奶和鸡蛋", .todo, 2900, true, nil, nil, nil, false, false),
        ("和团队讨论新需求的方向", .todo, 3200, false, 1, 10, 0, false, false),
        ("预约牙医", .todo, 3300, false, 1, 15, 0, false, false),
    ]

    private static func insertSamples(into context: ModelContext) {
        let calendar = Calendar.current
        let today = DayPlanner.normalizedDay(Date())
        let now = Date()
        for (text, kind, minutesAgo, done, dayOffset, hour, minute, pinned, highlighted) in samples {
            let created = now.addingTimeInterval(-Double(minutesAgo) * 60)
            var day: Date? = nil
            var time: Date? = nil
            if let dayOffset {
                day = calendar.date(byAdding: .day, value: dayOffset, to: today)
                if let hour, let day {
                    time = calendar.date(bySettingHour: hour, minute: minute ?? 0, second: 0, of: day)
                }
            }
            let record = Record(
                text: text,
                kind: kind,
                createdAt: created,
                isDone: done,
                dueDay: day,
                dueTime: time,
                wantsReminder: kind == .todo,
                isPinned: pinned,
                isHighlighted: highlighted
            )
            context.insert(record)
        }
    }
}
#endif
