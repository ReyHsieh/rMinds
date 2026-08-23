import WidgetKit
import SwiftUI
import SwiftData

// rDos 小组件：锁屏（环形/矩形/内联）+ 桌面（小/中/大）。
// 数据从 App Group 容器里的 SwiftData 库只读快照。

// MARK: - 时间线条目

struct TaskEntry: TimelineEntry {
    let date: Date
    let today: [TaskItem]
    let upcoming: [(label: String, task: TaskItem)]
    let dayStartHour: Int
    let dayStartMinute: Int

    var todayTotal: Int { today.count }
    var todayDone: Int { today.filter(\.isCompleted).count }
    var nextTask: TaskItem? {
        today.first { !$0.isCompleted } ?? today.first
    }
}

extension TaskEntry {
    static func load() -> TaskEntry {
        let defaults = SharedStore.userDefaults
        let hour = defaults.object(forKey: "settings.dayStartHour") as? Int ?? 4
        let minute = defaults.object(forKey: "settings.dayStartMinute") as? Int ?? 0

        var all: [TaskItem] = []
        if let url = SharedStore.storeURL,
           let container = try? ModelContainer(
               for: TaskItem.self,
               configurations: ModelConfiguration(url: url)
           ) {
            let context = ModelContext(container)
            all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        }

        let dayStart = DayPlanner.currentDayStart(hour: hour, minute: minute)
        let active = all.filter { task in
            if task.isArchived { return false }
            if task.isCompleted, let done = task.completedAt {
                return done >= dayStart
            }
            return true
        }
        .filter { $0.day != nil }

        let today = active
            .filter { DayPlanner.dayIndex(of: $0.day!, hour: hour, minute: minute) == 0 }
            .sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }

        let future = active.filter {
            DayPlanner.dayIndex(of: $0.day!, hour: hour, minute: minute) >= 1
        }
        let futureGroups = Dictionary(grouping: future) { $0.day! }

        var upcoming: [(label: String, task: TaskItem)] = []
        for day in futureGroups.keys.sorted() {
            let index = DayPlanner.dayIndex(of: day, hour: hour, minute: minute)
            let label = DayPlanner.dayLabel(for: index, day: day)
                .replacingOccurrences(of: " · ", with: " ")
                .capitalized
            let rows = (futureGroups[day] ?? [])
                .sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
            for task in rows.prefix(3) {
                upcoming.append((label, task))
            }
        }
        upcoming.sort { ($0.task.time ?? .distantPast) < ($1.task.time ?? .distantPast) }

        return TaskEntry(
            date: Date(),
            today: today,
            upcoming: upcoming,
            dayStartHour: hour,
            dayStartMinute: minute
        )
    }
}

struct TaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: Date(), today: [], upcoming: [], dayStartHour: 4, dayStartMinute: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(TaskEntry.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = TaskEntry.load()
        // 每小时自刷新一次；app 内数据变化时会主动 reload
        let next = Calendar.current.date(byAdding: .minute, value: 55, to: Date())
            ?? Date(timeIntervalSinceNow: 3300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - 通用小组件 UI

struct rDosWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TaskEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        case .systemSmall:
            small
        case .systemLarge:
            large
        default:
            medium
        }
    }

    // MARK: 锁屏

    private var circular: some View {
        let fraction = entry.todayTotal == 0 ? 0.0 : Double(entry.todayDone) / Double(entry.todayTotal)
        return ZStack {
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 34, height: 34)
            if entry.todayTotal == 0 {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
            } else {
                Text("\(entry.todayDone)/\(entry.todayTotal)")
                    .font(.system(size: 12, weight: .bold))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TODAY · \(entry.todayDone)/\(entry.todayTotal)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if let next = entry.nextTask {
                Text(next.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                if let time = next.time {
                    Text(DayPlanner.hm(time))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("没有任务")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        if let next = entry.nextTask {
            Text("\(entry.todayDone)/\(entry.todayTotal) · \(next.title)")
        } else {
            Text("今天 \(entry.todayDone)/\(entry.todayTotal)")
        }
    }

    // MARK: 桌面

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(DayPlanner.uppercaseShortDate(entry.date))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("\(entry.todayDone)/\(entry.todayTotal)")
                .font(.system(size: 38, weight: .heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let next = entry.nextTask {
                Text(next.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let time = next.time {
                    Text(DayPlanner.hm(time))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("没有任务")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color(white: 0.97) }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.system(size: 15, weight: .semibold))
                Text(DayPlanner.uppercaseShortDate(entry.date))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.todayDone)/\(entry.todayTotal)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            if entry.today.isEmpty {
                Spacer()
                Text("今天没有任务")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(Array(entry.today.prefix(4).enumerated()), id: \.offset) { _, task in
                    row(task)
                }
                if entry.today.count > 4 {
                    Text("还有 \(entry.today.count - 4) 项")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(for: .widget) { Color(white: 0.97) }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.system(size: 16, weight: .semibold))
                Text(DayPlanner.uppercaseShortDate(entry.date))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.todayDone)/\(entry.todayTotal)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(entry.today.prefix(6).enumerated()), id: \.offset) { _, task in
                row(task)
            }
            if !entry.upcoming.isEmpty {
                Spacer(minLength: 2)
                Text("COMING UP")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                ForEach(Array(entry.upcoming.prefix(4).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(.secondary.opacity(0.5), lineWidth: 1)
                            .frame(width: 10, height: 10)
                        Text(item.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(item.task.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let time = item.task.time {
                            Text(DayPlanner.hm(time))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color(white: 0.97) }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(task.isCompleted ? Color.primary : Color.clear)
                RoundedRectangle(cornerRadius: 3.5)
                    .strokeBorder(task.isCompleted ? Color.clear : Color.secondary.opacity(0.6), lineWidth: 1)
                if task.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Color(white: 0.97))
                }
            }
            .frame(width: 13, height: 13)
            Text(task.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let time = task.time {
                Text(DayPlanner.hm(time))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widget 声明

struct rDosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.reyhsiehchang.rDos.widget", provider: TaskProvider()) { entry in
            rDosWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("rDos")
        .description("今天的任务与进度，以及即将到来的安排。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

@main
struct rDosWidgetBundle: WidgetBundle {
    var body: some Widget {
        rDosWidget()
    }
}
