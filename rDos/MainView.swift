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
        case timeline = "时间线"
        case tags = "分类"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(OnboardingManager.self) private var onboarding
    @Query(sort: \Record.createdAt, order: .reverse) private var records: [Record]

    @Namespace private var tabNamespace
    @SceneStorage("main.selectedTab") private var tabRawValue: String = Tab.timeline.rawValue
    @State private var selectedTag: String?
    @State private var showEditor = false
    @State private var editingRecord: Record?
    @State private var presetPhoto: Data?
    @State private var presetVoice: (fileName: String, duration: TimeInterval)?
    @State private var showSettings = false
    @State private var frames: [String: CGRect] = [:]
    @State private var headerHeight: CGFloat = 0
    @State private var recordCountBeforeEditor = 0

    private var tab: Tab {
        get { Tab(rawValue: tabRawValue) ?? .timeline }
        nonmutating set { tabRawValue = newValue.rawValue }
    }

    private var recordActions: RecordActions {
        RecordActions(
            onToggleDone: toggleDone,
            onEdit: openEditor,
            onDelete: deleteRecord
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

            if tab == .timeline {
                RecordInputBar(
                    onSend: quickAdd,
                    onPickPhoto: { data in
                        presetPhoto = data
                        editingRecord = nil
                        showEditor = true
                    },
                    onVoiceDone: { fileName, duration in
                        presetVoice = (fileName, duration)
                        editingRecord = nil
                        showEditor = true
                    }
                )
                .reportFrame("inputBar")
            }

            if onboarding.isActive {
                OnboardingOverlay(frames: frames)
            }
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showEditor) {
            RecordEditorView(
                editing: editingRecord,
                presetPhoto: presetPhoto,
                presetVoice: presetVoice
            )
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
                recordCountBeforeEditor = records.count
            } else {
                onboarding.editorDismissed(createdTask: records.count > recordCountBeforeEditor)
                presetPhoto = nil
                presetVoice = nil
                refreshNotifications()
            }
        }
        .onPreferenceChange(FrameReporterKey.self) { value in
            frames = value
        }
        .onPreferenceChange(HeaderHeightKey.self) { value in
            headerHeight = value
        }
    }

    // 顶部：小号日期行 + 大标题 rMinds + 标签页 + 当前分类筛选指示。
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
                Text("rMinds")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(Color.primaryText)
                Spacer()
                Text(String(Calendar.current.component(.year, from: Date())))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.top, 5)

            tabsRow
                .padding(.top, 22)
        }
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 22)
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
        HStack(spacing: 26) {
            ForEach(Tab.allCases) { item in
                tabButton(item)
            }
            if let selectedTag {
                tagFilterChip
            }
            Spacer()
        }
    }

    private var tagFilterChip: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTag = nil }
        } label: {
            HStack(spacing: 4) {
                Text("#\(selectedTag!)")
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.onPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primaryText))
        }
        .buttonStyle(PressableStyle(scale: 0.93))
    }

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
                    Color.clear.frame(width: 28, height: 3)
                    if selected {
                        Capsule()
                            .fill(Color.primaryText)
                            .frame(width: 28, height: 3)
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
        case .timeline:
            TimelineView(
                records: records,
                actions: recordActions,
                contentTopInset: headerHeight,
                selectedTag: selectedTag
            )
        case .tags:
            TagsView(records: records) { tag in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTag = tag
                    tab = .timeline
                }
            }
        }
    }

    // MARK: 动作

    private func quickAdd(_ text: String, isTodo: Bool) {
        let record = Record(text: text, kind: isTodo ? .todo : .text)
        context.insert(record)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        onboarding.editorDismissed(createdTask: true)
    }

    private func openEditor(_ record: Record) {
        editingRecord = record
        showEditor = true
    }

    private func toggleDone(_ record: Record) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            record.isDone.toggle()
        }
        if record.isDone {
            NotificationManager.cancelRecord(record)
        } else if record.wantsReminder, settings.remindersEnabled {
            NotificationManager.scheduleRecord(id: record.id, title: record.text, time: record.dueTime)
        }
        onboarding.taskToggled(completed: record.isDone)
    }

    private func deleteRecord(_ record: Record) {
        NotificationManager.cancelRecord(record)
        if let file = record.voiceFileName {
            AudioHelper.shared.deleteVoiceFile(file)
        }
        withAnimation(.easeOut(duration: 0.2)) {
            context.delete(record)
        }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshNotifications() {
        NotificationManager.refreshRecords(records, enabled: settings.remindersEnabled)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
