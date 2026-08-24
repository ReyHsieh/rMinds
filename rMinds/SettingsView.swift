import SwiftUI
import SwiftData

/// 设置：外观（模式/强调色/图标）、字体、提醒、日程、数据、引导、关于。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var records: [Record]

    private var deletedRecords: [Record] {
        records.filter { $0.deletedAt != nil }.sorted { $0.deletedAt ?? .distantPast > $1.deletedAt ?? .distantPast }
    }

    @State private var exportText: String?
    @State private var confirmWipe = false
    @State private var iconError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("外观", selection: appearanceBinding) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("强调色", selection: accentBinding) {
                        ForEach(AccentTheme.allCases) { theme in
                            HStack(spacing: 6) {
                                Circle().fill(Color.accent(for: theme)).frame(width: 14, height: 14)
                                Text(theme.label)
                            }.tag(theme)
                        }
                    }
                } header: {
                    Text("外观")
                } footer: {
                    Text("强调色应用于发送按钮、待办勾选与高光标记。")
                }

                Section {
                    Picker("App 图标", selection: iconBinding) {
                        Text("气泡（默认）").tag("AppIcon")
                        Text("墨黑").tag("AppIconDark")
                        Text("描边").tag("AppIconLine")
                    }
                } header: {
                    Text("App 图标")
                } footer: {
                    if let iconError {
                        Text(iconError).foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("字体大小", selection: fontSizeBinding) {
                        ForEach(FontSizeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("通用")
                } footer: {
                    Text("调整时间线与输入的字号。")
                }

                Section {
                    Toggle("到期提醒通知", isOn: remindersBinding)
                } header: {
                    Text("提醒")
                } footer: {
                    Text("带时间的待办到达设定时刻时发送通知。需要系统通知权限；关闭后所有待发提醒会被清除。")
                }

                Section {
                    DatePicker(
                        "每日开始时间",
                        selection: dayStartTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    Text("日程")
                } footer: {
                    Text("“今天” 从几点开始。影响小组件里“今日待办”的统计口径；时间线按自然日（零点）分组。")
                }

                Section {
                    Picker("双击条目", selection: doubleTapBinding) {
                        ForEach([GestureAction.none, .toggleHighlight, .toggleDone, .togglePin]) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    Picker("长按条目", selection: longPressBinding) {
                        ForEach([GestureAction.none, .toggleHighlight, .togglePin, .edit]) { action in
                            Text(action.label).tag(action)
                        }
                    }
                } header: {
                    Text("手势")
                } footer: {
                    Text("自定义时间线上的快捷手势。单击始终为打开编辑。")
                }

                Section {
                    NavigationLink {
                        DeletedRecordsView()
                    } label: {
                        Label("最近删除", systemImage: "arrow.uturn.backward.circle")
                        Spacer()
                        Text("\(deletedRecords.count) 条")
                            .foregroundStyle(Color.secondaryText)
                    }
                    Button {
                        exportRecords()
                    } label: {
                        Label("导出全部记录（文本）", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        confirmWipe = true
                    } label: {
                        Label("清空全部记录", systemImage: "trash")
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("记录仅保存在本机。导出生成纯文本，可通过系统分享保存。")
                }

                Section {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("记录数", value: "\(records.count)")
                } header: {
                    Text("关于")
                }

                #if DEBUG
                Section {
                    Button {
                        SeedData.loadSample(context: context)
                    } label: {
                        Label("载入示例数据", systemImage: "square.grid.2x2")
                    }
                } header: {
                    Text("开发者选项（仅调试构建）")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: Binding(
                get: { exportText.map { ExportPayload(text: $0) } },
                set: { _ in exportText = nil }
            )) { payload in
                ShareSheet(items: [payload.text])
            }
            .confirmationDialog("清空全部记录？此操作不可撤销。", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("清空", role: .destructive) { wipeAll() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    struct ExportPayload: Identifiable {
        let text: String
        var id: String { "export" }
    }

    // MARK: 动作

    private func exportRecords() {
        let sorted = records.filter { $0.deletedAt == nil }.sorted { $0.createdAt < $1.createdAt }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var lines: [String] = ["rMinds 记录导出", ""]
        var lastDay = ""
        for record in sorted {
            let day = DayPlanner.localizedDate(record.createdAt)
            if day != lastDay {
                lines.append("— \(day) —")
                lastDay = day
            }
            let flag = record.isPinned ? "📌 " : (record.isHighlighted ? "✨ " : "")
            let mark = record.isTodo ? (record.isDone ? "[x] " : "[ ] ") : ""
            let time = DayPlanner.hm(record.createdAt)
            var line = "\(time) \(flag)\(mark)\(record.text)"
            if record.kind == .photo { line += "　[照片]" }
            if record.kind == .voice { line += String(format: "　[语音 %d:%02d]", Int(record.voiceDuration) / 60, Int(record.voiceDuration) % 60) }
            if let transcript = record.transcript, !transcript.isEmpty { line += "\n    转写：\(transcript)" }
            lines.append(line)
        }
        exportText = lines.joined(separator: "\n")
    }

    private func wipeAll() {
        for record in records {
            if let file = record.voiceFileName {
                AudioHelper.shared.deleteVoiceFile(file)
            }
            context.delete(record)
        }
        try? context.save()
    }

    // MARK: 绑定

    private var iconBinding: Binding<String> {
        Binding(
            get: { UIApplication.shared.alternateIconName ?? "AppIcon" },
            set: { name in
                let target = name == "AppIcon" ? nil : name
                UIApplication.shared.setAlternateIconName(target) { error in
                    iconError = error.map { "图标切换失败：\($0.localizedDescription)" }
                }
            }
        )
    }

    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { settings.remindersEnabled },
            set: { enabled in
                if enabled {
                    settings.remindersEnabled = true
                    NotificationManager.requestAuthorization { granted in
                        if granted {
                            NotificationManager.refreshRecords(records, enabled: true)
                        } else {
                            settings.remindersEnabled = false
                        }
                    }
                } else {
                    settings.remindersEnabled = false
                    NotificationManager.cancelAll()
                }
            }
        )
    }

    private var dayStartTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.dayStartHour,
                    minute: settings.dayStartMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.dayStartHour = components.hour ?? 4
                settings.dayStartMinute = components.minute ?? 0
            }
        )
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(get: { settings.appearance }, set: { settings.appearance = $0 })
    }

    private var fontSizeBinding: Binding<FontSizeMode> {
        Binding(get: { settings.fontSize }, set: { settings.fontSize = $0 })
    }

    private var accentBinding: Binding<AccentTheme> {
        Binding(get: { settings.accent }, set: { settings.accent = $0 })
    }

    private var doubleTapBinding: Binding<GestureAction> {
        Binding(get: { settings.doubleTapAction }, set: { settings.doubleTapAction = $0 })
    }

    private var longPressBinding: Binding<GestureAction> {
        Binding(get: { settings.longPressAction }, set: { settings.longPressAction = $0 })
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// 系统分享
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}


/// 最近删除：查看被删除的记录，可恢复或彻底删除。
struct DeletedRecordsView: View {
    @Environment(\.modelContext) private var context
    @Query private var records: [Record]
    @State private var confirmClear = false

    private var deletedRecords: [Record] {
        records.filter { $0.deletedAt != nil }.sorted { $0.deletedAt ?? .distantPast > $1.deletedAt ?? .distantPast }
    }

    var body: some View {
        Group {
            if deletedRecords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "trash.slash")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.secondaryText.opacity(0.6))
                    Text("回收站是空的")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(deletedRecords) { record in
                        row(record)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("最近删除")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !deletedRecords.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("恢复全部") {
                        for record in deletedRecords {
                            record.deletedAt = nil
                        }
                        try? context.save()
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("清空回收站", systemImage: "trash")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            }
        }
        .confirmationDialog("彻底删除全部记录？不可恢复。", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("彻底删除", role: .destructive) { purgeAll() }
            Button("取消", role: .cancel) {}
        }
    }

    private func row(_ record: Record) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    record.deletedAt = nil
                }
                try? context.save()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accent(for: AppSettings.shared.accent))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.text.isEmpty ? kindLabel(record) : record.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(2)
                Text(deletedText(record))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
            Button {
                purge(record)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func purge(_ record: Record) {
        if let file = record.voiceFileName {
            AudioHelper.shared.deleteVoiceFile(file)
        }
        withAnimation { context.delete(record) }
        try? context.save()
    }

    private func purgeAll() {
        for record in deletedRecords {
            purge(record)
        }
    }

    private func kindLabel(_ record: Record) -> String {
        switch record.kind {
        case .text: return "文字记录"
        case .todo: return "待办"
        case .photo: return "照片"
        case .voice: return "语音"
        }
    }

    private func deletedText(_ record: Record) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm 删除"
        return formatter.string(from: record.deletedAt ?? record.createdAt)
    }
}
