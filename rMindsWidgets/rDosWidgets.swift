import WidgetKit
import SwiftUI
import SwiftData

// rMinds 小组件：锁屏（环形/矩形/内联）+ 桌面（小/中/大）。
// 数据从 App Group 容器里的 SwiftData 库只读快照。

// MARK: - 时间线条目

struct RecordEntry: TimelineEntry {
    struct TodoItem {
        let text: String
        let isDone: Bool
        let timeText: String?
    }

    struct FeedItem {
        let icon: String
        let text: String
        let timeText: String
    }

    let date: Date
    let todos: [TodoItem]
    let feed: [FeedItem]
    let todayCount: Int

    var done: Int { todos.filter(\.isDone).count }
    var total: Int { todos.count }
    var nextTodo: TodoItem? { todos.first { !$0.isDone } }
    var latest: FeedItem? { feed.first }
}

extension RecordEntry {
    static func load() -> RecordEntry {
        var all: [Record] = []
        if let url = SharedStore.storeURL,
           let container = try? ModelContainer(
               for: Record.self,
               configurations: ModelConfiguration(url: url)
           ) {
            let context = ModelContext(container)
            all = (try? context.fetch(FetchDescriptor<Record>())) ?? []
        }
        all.removeAll { $0.deletedAt != nil }
        all.sort { $0.createdAt > $1.createdAt }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        let todos = all
            .filter { $0.isTodo && ($0.dueDay == nil || $0.dueDay! >= calendar.date(byAdding: .day, value: -1, to: startOfToday)!) }
            .prefix(8)
            .map { record in
                TodoItem(
                    text: record.text,
                    isDone: record.isDone,
                    timeText: record.dueTime.map { DayPlanner.hm($0) }
                )
            }

        let feed = Array(all.prefix(8)).map { record in
            FeedItem(
                icon: icon(for: record),
                text: record.text.isEmpty ? "—" : record.text,
                timeText: DayPlanner.hm(record.createdAt)
            )
        }

        let today = DayPlanner.normalizedDay(Date())
        let todayCount = all.filter { DayPlanner.normalizedDay($0.createdAt) == today }.count
        return RecordEntry(date: Date(), todos: Array(todos), feed: feed, todayCount: todayCount)
    }

    private static func icon(for record: Record) -> String {
        switch record.kind {
        case .text: return "text.quote"
        case .todo: return record.isDone ? "checkmark.circle.fill" : "circle"
        case .photo: return "photo"
        case .voice: return "waveform"
        }
    }
}

struct RecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordEntry {
        RecordEntry(date: Date(), todos: [], feed: [], todayCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecordEntry) -> Void) {
        completion(RecordEntry.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordEntry>) -> Void) {
        let entry = RecordEntry.load()
        // 每小时自刷新一次；app 内数据变化时会主动 reload
        let next = Calendar.current.date(byAdding: .minute, value: 55, to: Date())
            ?? Date(timeIntervalSinceNow: 3300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - 小组件 UI

struct rMindsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecordEntry

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
        let fraction: Double = entry.total > 0
            ? Double(entry.done) / Double(entry.total)
            : (entry.todayCount > 0 ? 1.0 : 0.0)
        return ZStack {
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 34, height: 34)
            if entry.todayCount == 0 {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
            } else {
                VStack(spacing: 0) {
                    Text("\(entry.todayCount)")
                        .font(.system(size: 13, weight: .heavy))
                    Text("条")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("今日 \(entry.todayCount) 条")
                if entry.total > 0 {
                    Text("· 待办 \(entry.done)/\(entry.total)")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            if let latest = entry.latest {
                HStack(spacing: 5) {
                    Image(systemName: latest.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(latest.text)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                }
                Text(latest.timeText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            } else {
                Text("记录此刻")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        if let latest = entry.latest {
            Text("今日 \(entry.todayCount) 条 · \(latest.text)")
        } else {
            Text("记录此刻")
        }
    }

    // MARK: 桌面

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(DayPlanner.uppercaseShortDate(entry.date))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entry.total > 0 {
                Text("\(entry.done)/\(entry.total)")
                    .font(.system(size: 34, weight: .heavy))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("待办 · 今日 \(entry.todayCount) 条记录")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("\(entry.todayCount)")
                    .font(.system(size: 38, weight: .heavy))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("条记录")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 2)
            if let latest = entry.feed.first {
                HStack(spacing: 5) {
                    Image(systemName: latest.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(latest.text)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                }
            } else {
                Text("记录此刻")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    /// 中号：小号的头部（日期时间 + 今日条数 + 进度大数字）+ 待办列表，顶部对齐
    private var medium: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日 · \(DayPlanner.uppercaseShortDate(entry.date)) \(DayPlanner.hm(entry.date))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.todayCount) 条记录")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if entry.total > 0 {
                Text("\(entry.done)/\(entry.total)")
                    .font(.system(size: 28, weight: .heavy))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if entry.todayCount > 0 {
                Text("\(entry.todayCount)")
                    .font(.system(size: 28, weight: .heavy))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if entry.todos.isEmpty {
                Text("没有待办，随手记点什么吧")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(entry.todos.prefix(3).enumerated()), id: \.offset) { _, todo in
                    todoRow(todo.text, done: todo.isDone, time: todo.timeText)
                }
                if entry.todos.count > 3 {
                    Text("还有 \(entry.todos.count - 3) 项")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("待办 · \(entry.done)/\(entry.total)")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(DayPlanner.uppercaseShortDate(entry.date))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(entry.todos.prefix(5).enumerated()), id: \.offset) { _, todo in
                todoRow(todo.text, done: todo.isDone, time: todo.timeText)
            }
            if entry.feed.contains(where: { !$0.text.isEmpty }) {
                Spacer(minLength: 2)
                Text("最近记录")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                ForEach(Array(entry.feed.prefix(5).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 7) {
                        Image(systemName: item.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(item.text)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(item.timeText)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    private func todoRow(_ text: String, done: Bool, time: String?) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(done ? Color.primary : Color.clear)
                RoundedRectangle(cornerRadius: 3.5)
                    .strokeBorder(done ? Color.clear : Color.secondary.opacity(0.6), lineWidth: 1)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
            }
            .frame(width: 13, height: 13)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(done ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let time {
                Text(time)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widget 声明

struct rMindsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.reyhsiehchang.rDos.widget", provider: RecordProvider()) { entry in
            rMindsWidgetView(entry: entry)
        }
        .configurationDisplayName("rMinds")
        .description("待办进度与最新记录。")
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
struct rMindsWidgetBundle: WidgetBundle {
    var body: some Widget {
        rMindsWidget()
    }
}
