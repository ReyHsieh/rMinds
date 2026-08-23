import SwiftUI

/// Home 标签：
/// - Today 卡片（仅今天，扁平暖灰底）
/// - Coming up 模块：今天之后（含明天）按天顺序展示，每带一天标签；不含未定日期任务
/// - 已过期未完成任务排在最前，同样带日期标签
struct HomeView: View {
    let tasks: [TaskItem]
    var dayStartHour: Int
    var dayStartMinute: Int
    let actions: TaskActions
    /// 顶部 header 高度，内容从其下开始但可滚到 header 底下（渐隐遮挡）
    var contentTopInset: CGFloat

    private struct DayGroup: Identifiable {
        let day: Date
        let index: Int
        let label: String
        let tasks: [TaskItem]
        var id: Date { day }
    }

    private var groups: [DayGroup] {
        let dictionary = Dictionary(grouping: tasks) { $0.day! }
        return dictionary.keys.sorted().map { day in
            let index = DayPlanner.dayIndex(of: day, hour: dayStartHour, minute: dayStartMinute)
            let rows = (dictionary[day] ?? []).sorted {
                ($0.time ?? .distantPast) < ($1.time ?? .distantPast)
            }
            return DayGroup(
                day: day,
                index: index,
                label: DayPlanner.dayLabel(for: index, day: day),
                tasks: rows
            )
        }
    }

    private var overdueGroups: [DayGroup] { groups.filter { $0.index < 0 } }
    private var todayGroup: DayGroup? { groups.first { $0.index == 0 } }
    private var futureGroups: [DayGroup] { groups.filter { $0.index >= 1 } }
    private var futureCount: Int { futureGroups.reduce(0) { $0 + $1.tasks.count } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if groups.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: "今天没有任务",
                        subtitle: "点击下方 “New task” 添加一个"
                    )
                } else {
                    ForEach(overdueGroups) { group in
                        plainGroup(group)
                    }

                    if let today = todayGroup {
                        todayCard(today)
                    }

                    if !futureGroups.isEmpty {
                        comingUp
                    }
                }
            }
            .padding(.top, contentTopInset + 6)
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Today 卡片

    private func todayCard(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "Today",
                subtitle: DayPlanner.uppercaseShortDate(group.day),
                countText: "\(group.tasks.filter(\.isCompleted).count) / \(group.tasks.count)"
            )
            ForEach(Array(group.tasks.enumerated()), id: \.element.persistentModelID) { position, task in
                row(task, subtitle: timeSubtitle(task))
                    .reportFrame(position == 0 ? "firstTask" : nil)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Coming up

    private var comingUp: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Coming up", subtitle: nil, countText: "\(futureCount)")
            ForEach(futureGroups) { group in
                plainGroup(group)
            }
        }
    }

    /// 带日期标签的普通分组（Coming up 内的每一天 / 过期任务），滑动内容裁剪在自身边界内
    private func plainGroup(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.secondaryText)
                .padding(.leading, 2)
            ForEach(group.tasks) { task in
                row(task, subtitle: timeSubtitle(task))
            }
        }
        .clipped()
    }

    // MARK: 通用

    private func sectionHeader(title: String, subtitle: String?, countText: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
            Text(countText)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.secondaryText)
        }
    }

    private func row(_ task: TaskItem, subtitle: String?) -> some View {
        TaskRowView(
            task: task,
            subtitle: subtitle,
            context: .active,
            actions: actions
        )
    }

    private func timeSubtitle(_ task: TaskItem) -> String? {
        task.time.map { DayPlanner.hm($0) }
    }
}

/// Someday / Archive 用的通用卡片分组（滑动内容裁剪在卡片内）。
struct TaskSectionCard: View {
    let title: String
    let subtitle: String?
    let countText: String
    let tasks: [TaskItem]
    let rowContext: TaskRowView.RowContext
    let actions: TaskActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                Text(countText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.secondaryText)
            }
            ForEach(tasks) { task in
                TaskRowView(
                    task: task,
                    subtitle: nil,
                    context: rowContext,
                    actions: actions
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct EmptyStateView: View {
    var icon: String = "tray"
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.secondaryText.opacity(0.6))
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
            Text(subtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.secondaryText.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}
