import SwiftUI

/// Someday 标签：无日期任务。
struct SomedayView: View {
    let tasks: [TaskItem]
    let actions: TaskActions
    var contentTopInset: CGFloat

    private var sortedTasks: [TaskItem] {
        tasks.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if tasks.isEmpty {
                    EmptyStateView(
                        icon: "sparkles",
                        title: "还没有 “某天” 任务",
                        subtitle: "把还不确定何时做的事先放在这里"
                    )
                } else {
                    TaskSectionCard(
                        title: "Someday",
                        subtitle: nil,
                        countText: "\(tasks.count)",
                        tasks: sortedTasks,
                        rowContext: .active,
                        actions: actions
                    )
                }
            }
            .padding(.top, contentTopInset + 4)
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
    }
}

/// Archive 标签：手动归档 + 往期已完成的任务，按归档/完成日倒序分组。
/// 左滑删除，右滑恢复。
struct ArchiveView: View {
    let tasks: [TaskItem]
    let actions: TaskActions
    var contentTopInset: CGFloat

    private var sections: [(day: Date, tasks: [TaskItem])] {
        let groups = Dictionary(grouping: tasks) {
            DayPlanner.normalizedDay($0.archivedAt ?? $0.completedAt ?? $0.createdAt)
        }
        return groups.keys.sorted(by: >).map { day in
            (day, (groups[day] ?? []).sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if tasks.isEmpty {
                    EmptyStateView(
                        icon: "archivebox",
                        title: "归档是空的",
                        subtitle: "左滑任务可手动归档；已完成的任务会在次日出现在这里"
                    )
                } else {
                    ForEach(sections, id: \.day) { section in
                        TaskSectionCard(
                            title: DayPlanner.uppercaseShortDate(section.day),
                            subtitle: DayPlanner.weekdayLabel(section.day),
                            countText: "\(section.tasks.count)",
                            tasks: section.tasks,
                            rowContext: .archive,
                            actions: actions
                        )
                    }
                }
            }
            .padding(.top, contentTopInset + 4)
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
    }
}
