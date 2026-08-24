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
    @Query(sort: \Record.createdAt, order: .reverse) private var records: [Record]

    @State private var showEditor = false
    @State private var editingRecord: Record?
    @State private var showSettings = false
    @State private var showQuotePicker = false
    @State private var pendingQuote: Record?
    @State private var headerHeight: CGFloat = 0
    @State private var quoteJumpID: PersistentIdentifier?

    private var visibleRecords: [Record] {
        records.filter { $0.deletedAt == nil }
    }

    private var recordActions: RecordActions {
        RecordActions(
            onToggleDone: toggleDone,
            onEdit: openEditor,
            onDelete: deleteRecord,
            onQuoteTap: { quoted in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    quoteJumpID = quoted.persistentModelID
                }
            },
            quoteProvider: { id in
                visibleRecords.first { $0.id == id }
            }
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
                onRequestQuotePicker: {
                    editingRecord = nil
                    showQuotePicker = true
                },
                pendingQuote: $pendingQuote
            )
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showEditor) {
            if let record = editingRecord {
                RecordEditorView(editing: record)
            }
        }
        .sheet(isPresented: $showQuotePicker) {
            QuotePickerSheet(records: visibleRecords) { record in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    pendingQuote = record
                }
                showQuotePicker = false
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            refreshNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshNotifications() }
        }
        .onChange(of: settings.remindersEnabled) {
            refreshNotifications()
        }
        .onChange(of: showEditor) { _, shown in
            if !shown {
                refreshNotifications()
            }
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
            records: visibleRecords,
            actions: recordActions,
            contentTopInset: headerHeight,
            jumpTargetID: $quoteJumpID
        )
        // 字号缩放是静态量，时间线无响应式依赖；用 id 在切换时整树重建
        .id(settings.fontSize)
    }

    // MARK: 动作

    private func quickAdd(_ draft: OutgoingDraft) {
        let kind: Record.Kind = draft.isTodo ? .todo : (draft.photo != nil ? .photo : (draft.voice != nil ? .voice : .text))
        let record = Record(
            text: draft.text,
            kind: kind,
            dueDay: draft.dueDay,
            quoteID: draft.quoteID,
            photoData: draft.photo,
            voiceFileName: draft.voice?.fileName,
            voiceDuration: draft.voice?.duration ?? 0
        )
        context.insert(record)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
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
    }

    private func deleteRecord(_ record: Record) {
        NotificationManager.cancelRecord(record)
        withAnimation(.easeOut(duration: 0.2)) {
            record.deletedAt = Date()   // 软删除，可在设置 → 最近删除恢复
        }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshNotifications() {
        NotificationManager.refreshRecords(visibleRecords, enabled: settings.remindersEnabled)
        WidgetCenter.shared.reloadAllTimelines()
    }
}


/// 引用选择器：从最近的记录里挑一条引用
struct QuotePickerSheet: View {
    let records: [Record]
    var onSelect: (Record) -> Void

    var body: some View {
        NavigationStack {
            List(records.prefix(50)) { record in
                Button {
                    onSelect(record)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: QuotePickerSheet.kindIcon(record))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.secondaryText)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.text.isEmpty ? QuotePickerSheet.kindLabel(record) : record.text)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.primaryText)
                                .lineLimit(1)
                            Text(DayPlanner.localizedDate(record.createdAt) + " " + DayPlanner.hm(record.createdAt))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "quote.opening")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondaryText.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("选择引用")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { }
                }
            }
        }
    }

    static func kindIcon(_ record: Record) -> String {
        switch record.kind {
        case .text: return "text.quote"
        case .todo: return record.isDone ? "checkmark.circle.fill" : "circle"
        case .photo: return "photo"
        case .voice: return "waveform"
        }
    }

    static func kindLabel(_ record: Record) -> String {
        switch record.kind {
        case .text: return "文字记录"
        case .todo: return "待办"
        case .photo: return "照片"
        case .voice: return "语音"
        }
    }
}
