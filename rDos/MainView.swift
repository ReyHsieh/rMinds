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
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(OnboardingManager.self) private var onboarding
    @Query(sort: \Record.createdAt, order: .reverse) private var records: [Record]

    @State private var showEditor = false
    @State private var editingRecord: Record?
    @State private var presetPhoto: Data?
    @State private var presetVoice: (fileName: String, duration: TimeInterval)?
    @State private var showSettings = false
    @State private var frames: [String: CGRect] = [:]
    @State private var headerHeight: CGFloat = 0
    @State private var recordCountBeforeEditor = 0

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

        }
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 14)
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

    @ViewBuilder
    private var content: some View {
        TimelineView(
            records: records,
            actions: recordActions,
            contentTopInset: headerHeight
        )
        // 字号缩放是静态量，时间线无响应式依赖；用 id 在切换时整树重建
        .id(settings.fontSize)
    }

    // MARK: 动作

    private func quickAdd(_ text: String, dueDay: Date?, isTodo: Bool) {
        let record = Record(text: text, kind: isTodo ? .todo : .text, dueDay: dueDay)
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
