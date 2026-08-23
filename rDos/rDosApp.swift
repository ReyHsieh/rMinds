import SwiftUI
import SwiftData
import WidgetKit

@main
struct rDosApp: App {
    @State private var settings = AppSettings.shared
    @State private var onboarding = OnboardingManager.shared

    let container: ModelContainer

    init() {
        do {
            // 数据库放在 App Group 容器，供小组件扩展读取
            if let url = SharedStore.storeURL {
                container = try ModelContainer(
                    for: TaskItem.self,
                    configurations: ModelConfiguration(url: url)
                )
            } else {
                container = try ModelContainer(for: TaskItem.self)
            }
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
                .environment(onboarding)
                .preferredColorScheme(settings.appearance.colorScheme)
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

    /// (标题, 天偏移, 时(=nil 无时间), 分, 是否已完成)
    private static let samples: [(String, Int, Int?, Int, Bool)] = [
        ("整理本周的产品草图", 0, 9, 0, false),
        ("确认首页的中文文案", 0, 11, 30, true),
        ("给植物浇水", 0, 14, 0, true),
        ("买牛奶和鸡蛋", 0, 17, 30, true),
        ("发送项目周报邮件", 1, nil, 0, false),
        ("预约牙医", 1, 15, 0, false),
        ("与团队讨论新需求", 4, 11, 0, false),
    ]

    private static func insertSamples(into context: ModelContext) {
        let calendar = Calendar.current
        let today = DayPlanner.normalizedDay(Date())
        let now = Date()
        for (title, dayOffset, hour, minute, done) in samples {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today)
            let time: Date?
            if let hour {
                time = day.flatMap {
                    calendar.date(bySettingHour: hour, minute: minute, second: 0, of: $0)
                }
            } else {
                time = nil
            }
            let task = TaskItem(
                title: title,
                day: day,
                time: time,
                wantsReminder: true,
                isCompleted: done,
                completedAt: done ? now : nil
            )
            context.insert(task)
        }
    }
}
#endif
