import SwiftUI
import SwiftData

/// 新建 / 编辑任务。
struct TaskEditorView: View {
    enum DayChoice: Hashable {
        case today, tomorrow, pick, someday
    }

    let editing: TaskItem?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var title = ""
    @State private var bodyText = ""
    @State private var choice: DayChoice = .today
    @State private var pickDate = Date()
    @State private var hasTime = false
    @State private var timeDate = Date()
    @State private var reminder = true
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    private let saveHaptic = UINotificationFeedbackGenerator()

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedDay: Date? {
        switch choice {
        case .today: return DayPlanner.normalizedDay(Date())
        case .tomorrow: return DayPlanner.normalizedDay(Date().addingTimeInterval(86_400))
        case .pick: return DayPlanner.normalizedDay(pickDate)
        case .someday: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            handle

            TextField("任务标题", text: $title, axis: .vertical)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.primaryText)
                .focused($titleFocused)
                .submitLabel(.done)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.cardTint)
                )

            bodyEditor

            card("日期", icon: "calendar") {
                chips
                if choice == .pick {
                    DatePicker(
                        "",
                        selection: $pickDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }
            }

            if choice != .someday {
                card("时间", icon: "clock") {
                    Toggle("添加时间", isOn: $hasTime)
                        .font(.system(size: 16))
                    if hasTime {
                        DatePicker(
                            "",
                            selection: $timeDate,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        Toggle("到点提醒", isOn: $reminder)
                            .font(.system(size: 16))
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                if editing != nil {
                    Button {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color.cardTint))
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                }

                Spacer()

                Button("取消") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.secondaryText)
                .buttonStyle(PressableStyle(scale: 0.95))

                Button(action: save) {
                    Text("保存")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSave ? Color.onPrimary : Color.secondaryText)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            Capsule(style: .continuous)
                                .fill(canSave ? Color.primaryText : Color.disabledFill)
                        )
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(Color.appBackground)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            loadExisting()
            if editing == nil {
                // 新建时自动聚焦标题
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    titleFocused = true
                }
            }
        }
        .confirmationDialog("删除这个任务？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteAndDismiss() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: 子视图

    private var handle: some View {
        Capsule()
            .fill(Color.secondaryText.opacity(0.25))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    /// 正文输入（可选；首页不展示，进入编辑时呈现）
    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $bodyText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.primaryText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            if bodyText.isEmpty {
                Text("正文（可选）")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.secondaryText)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 19)
                    .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardTint)
        )
    }

    private func card<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.secondaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardTint)
        )
    }

    private var chips: some View {
        HStack(spacing: 8) {
            chip("今天", .today)
            chip("明天", .tomorrow)
            chip("选日期", .pick)
            chip("某天", .someday)
        }
    }

    private func chip(_ label: String, _ value: DayChoice) -> some View {
        let selected = choice == value
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { choice = value }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.onPrimary : Color.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? Color.primaryText : Color.chipFill)
                )
        }
        .buttonStyle(PressableStyle(scale: 0.93))
        .sensoryFeedback(.selection, trigger: choice)
    }

    // MARK: 逻辑

    private func loadExisting() {
        guard let editing, title.isEmpty else { return }
        title = editing.title
        bodyText = editing.bodyText
        if let day = editing.day {
            let index = DayPlanner.dayIndex(
                of: day,
                hour: settings.dayStartHour,
                minute: settings.dayStartMinute
            )
            switch index {
            case 0: choice = .today
            case 1: choice = .tomorrow
            default:
                choice = .pick
                pickDate = day
            }
        } else {
            choice = .someday
        }
        hasTime = editing.time != nil
        if let time = editing.time {
            timeDate = time
        } else if let day = resolvedDay,
                  let defaultTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) {
            timeDate = defaultTime
        }
        reminder = editing.wantsReminder
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let day = resolvedDay
        var time: Date? = nil
        if hasTime, let day {
            let components = Calendar.current.dateComponents([.hour, .minute], from: timeDate)
            time = Calendar.current.date(
                bySettingHour: components.hour ?? 9,
                minute: components.minute ?? 0,
                second: 0,
                of: day
            )
        }
        let wantsReminder = hasTime && reminder && time != nil

        if let editing {
            editing.title = trimmed
            editing.bodyText = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
            editing.day = day
            editing.time = time
            editing.wantsReminder = wantsReminder
            if editing.isCompleted {
                NotificationManager.cancel(editing)
            } else if wantsReminder {
                syncReminder(for: editing)
            }
        } else {
            let task = TaskItem(
                title: trimmed,
                bodyText: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                day: day,
                time: time,
                wantsReminder: wantsReminder
            )
            context.insert(task)
            if wantsReminder {
                syncReminder(for: task)
            }
        }
        try? context.save()
        saveHaptic.notificationOccurred(.success)
        dismiss()
    }

    private func syncReminder(for task: TaskItem) {
        if settings.remindersEnabled {
            NotificationManager.schedule(task)
        } else {
            NotificationManager.requestAndSchedule(task) { granted in
                if granted {
                    settings.remindersEnabled = true
                } else {
                    task.wantsReminder = false
                }
            }
        }
    }

    private func deleteAndDismiss() {
        guard let editing else { return }
        NotificationManager.cancel(editing)
        context.delete(editing)
        try? context.save()
        dismiss()
    }
}
