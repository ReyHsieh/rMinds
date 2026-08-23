import SwiftUI
import SwiftData
import WidgetKit

struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MainView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case home = "Home"
        case someday = "Someday"
        case archive = "Archive"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(OnboardingManager.self) private var onboarding
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]

    @Namespace private var tabNamespace
    @State private var tab: Tab = .home
    @State private var showEditor = false
    @State private var editingTask: TaskItem?
    @State private var showSettings = false
    @State private var frames: [String: CGRect] = [:]
    @State private var headerHeight: CGFloat = 0
    @State private var taskCountBeforeEditor = 0

    // MARK: 数据分组

    private var dayStart: Date {
        DayPlanner.currentDayStart(hour: settings.dayStartHour, minute: settings.dayStartMinute)
    }

    /// 未归档：当日（含当日完成）的一切任务
    private var activeTasks: [TaskItem] {
        tasks.filter { task in
            if task.isArchived { return false }
            if task.isCompleted, let done = task.completedAt {
                return done >= dayStart
            }
            return true
        }
    }

    private var homeTasks: [TaskItem] { activeTasks.filter { $0.day != nil } }
    private var somedayTasks: [TaskItem] { activeTasks.filter { $0.day == nil } }

    /// 手动归档 + 完成时间在当日开始之前的任务
    private var archiveTasks: [TaskItem] {
        tasks.filter { task in
            if task.isArchived { return true }
            return task.isCompleted && (task.completedAt ?? .distantPast) < dayStart
        }
    }

    private var taskActions: TaskActions {
        TaskActions(
            onToggle: toggle,
            onEdit: openEditor,
            onDelete: deleteTask,
            onArchive: archiveTask,
            onRestore: restoreTask
        )
    }

    // MARK: 布局

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .top) {
                content
                    .clipped()   // 阻止滚动内容画到状态栏/灵动岛区域
                header
            }

            newTaskButton

            if onboarding.isActive {
                OnboardingOverlay(frames: frames)
            }
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showEditor) {
            TaskEditorView(editing: editingTask)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            onboarding.startIfNeeded()
            refreshNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshNotifications() }
        }
        .onChange(of: settings.remindersEnabled) {
            refreshNotifications()
        }
        .onChange(of: showEditor) { _, shown in
            if shown {
                taskCountBeforeEditor = tasks.count
            } else {
                onboarding.editorDismissed(createdTask: tasks.count > taskCountBeforeEditor)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .onPreferenceChange(FrameReporterKey.self) { value in
            frames = value
        }
        .onPreferenceChange(HeaderHeightKey.self) { value in
            headerHeight = value
        }
    }

    // 顶部：小号日期行 + 大标题 rDos + 标签页。
    // 背景为实色渐隐遮挡（顶部含状态栏/灵动岛区域完全不透明，底部 28pt 渐隐）。
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(DayPlanner.uppercaseHeaderDate(Date()))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .padding(.top, 3)
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.primaryText)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
            }

            HStack(alignment: .firstTextBaseline) {
                Text("rDos")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(Color.primaryText)
                Spacer()
                Text(String(Calendar.current.component(.year, from: Date())))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.top, 5)

            tabsRow
                .padding(.top, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 24)
        .background {
            Rectangle()
                .fill(Color.appBackground)
                .ignoresSafeArea(edges: .top)
                .mask(
                    GeometryReader { proxy in
                        let height = proxy.size.height
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: max(0, (height - 28) / height)),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                )
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeaderHeightKey.self, value: proxy.size.height)
            }
        )
    }

    private var tabsRow: some View {
        HStack(spacing: 28) {
            ForEach(Tab.allCases) { item in
                tabButton(item)
            }
            Spacer()
        }
    }

    /// 标签按钮：下划线用 matchedGeometryEffect 在标签间平滑滑动
    private func tabButton(_ item: Tab) -> some View {
        let selected = tab == item
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { tab = item }
        } label: {
            VStack(spacing: 10) {
                Text(item.rawValue)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primaryText : Color.secondaryText)
                ZStack {
                    Color.clear.frame(width: 28, height: 3.5)
                    if selected {
                        Capsule()
                            .fill(Color.primaryText)
                            .frame(width: 28, height: 3.5)
                            .matchedGeometryEffect(id: "tabUnderline", in: tabNamespace)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.95, opacity: 0.7))
        .sensoryFeedback(.selection, trigger: tab)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home:
            HomeView(
                tasks: homeTasks,
                dayStartHour: settings.dayStartHour,
                dayStartMinute: settings.dayStartMinute,
                actions: taskActions,
                contentTopInset: headerHeight
            )
        case .someday:
            SomedayView(
                tasks: somedayTasks,
                actions: taskActions,
                contentTopInset: headerHeight
            )
        case .archive:
            ArchiveView(
                tasks: archiveTasks,
                actions: taskActions,
                contentTopInset: headerHeight
            )
        }
    }

    // 黑色胶囊主按钮（浅色=黑底白字，深色=白底黑字）
    private var newTaskButton: some View {
        Button {
            editingTask = nil
            showEditor = true
        } label: {
            Text("New task")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.onPrimary)
                .frame(width: 338, height: 52)
                .background(Capsule(style: .continuous).fill(Color.primaryText))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .sensoryFeedback(.impact(weight: .light), trigger: showEditor)
        .padding(.bottom, 2)
        .reportFrame("newTask")
    }

    // MARK: 动作

    private func openEditor(_ task: TaskItem) {
        editingTask = task
        showEditor = true
    }

    private func toggle(_ task: TaskItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? Date() : nil
        }
        if task.isCompleted {
            NotificationManager.cancel(task)
        } else if task.wantsReminder, settings.remindersEnabled {
            NotificationManager.schedule(task)
        }
        onboarding.taskToggled(completed: task.isCompleted)
    }

    private func deleteTask(_ task: TaskItem) {
        NotificationManager.cancel(task)
        withAnimation(.easeOut(duration: 0.2)) {
            context.delete(task)
        }
        try? context.save()
    }

    private func archiveTask(_ task: TaskItem) {
        NotificationManager.cancel(task)
        withAnimation(.easeOut(duration: 0.2)) {
            task.isArchived = true
            task.archivedAt = Date()
        }
        try? context.save()
    }

    private func restoreTask(_ task: TaskItem) {
        withAnimation(.easeOut(duration: 0.2)) {
            task.isArchived = false
            task.archivedAt = nil
            task.isCompleted = false
            task.completedAt = nil
        }
        try? context.save()
    }

    private func refreshNotifications() {
        NotificationManager.refreshPending(tasks: tasks, enabled: settings.remindersEnabled)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
