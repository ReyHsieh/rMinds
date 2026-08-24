import SwiftUI
import SwiftData
import PhotosUI

/// 记录编辑器：新建（照片/语音草稿）或编辑既有记录。
/// 待办可设置日期时间与提醒。
struct RecordEditorView: View {
    /// nil = 新建
    let editing: Record?
    /// 新建时预填的内容
    var presetPhoto: Data? = nil
    var presetVoice: (fileName: String, duration: TimeInterval)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var text = ""
    @State private var isTodo = false
    @State private var dueDay: Date? = nil
    @State private var dueTime: Date? = nil
    @State private var reminder = true
    @State private var isPinned = false
    @State private var isHighlighted = false
    @State private var photoData: Data?
    @State private var confirmDelete = false
    @FocusState private var textFocused: Bool

    private let saveHaptic = UINotificationFeedbackGenerator()
    private var audio = AudioHelper.shared

    private var canSave: Bool {
        if isTodo {
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || photoData != nil
            || (editing?.voiceFileName ?? presetVoice?.fileName) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(Color.secondaryText.opacity(0.25))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                if showAtMenu {
                    AtDateMenu(
                        onPickDay: { date in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isTodo = true
                                dueDay = date
                                showAtMenu = false
                            }
                        },
                        onSomeday: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isTodo = true
                                dueDay = nil
                                showAtMenu = false
                            }
                        },
                        onCustom: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isTodo = true
                                showAtMenu = false
                                showDatePicker = true
                            }
                        },
                        onCancel: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showAtMenu = false
                            }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                TextField(isTodo ? "待办内容" : "记录点什么…（@ 设为待办）", text: $text, axis: .vertical)
                    .font(.system(size: FS.s(20), weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .focused($textFocused)
                    .submitLabel(.done)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.cardTint)
                    )
                    .onChange(of: text) { _, new in
                        // 输入 @ 触发日期选择，并把 @ 从文本移除
                        if new.hasSuffix("@") {
                            text = String(new.dropLast())
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showAtMenu = true
                            }
                        }
                    }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showAtMenu)

            HStack(spacing: 8) {
                toggleChip("待办", icon: "checklist", on: isTodo) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isTodo.toggle()
                        if !isTodo {
                            dueDay = nil
                            dueTime = nil
                            showDatePicker = false
                            showTimePicker = false
                        }
                    }
                }
                Spacer()
            }

            if let data = effectivePhoto {
                photoPreview(data)
            }

            if let voice = effectiveVoice {
                voicePreview(voice)
            }

            if isTodo {
                scheduleCard
            }

            flagCard

                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
                Button("取消") { dismiss() }
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
                                .fill(canSave ? Color.accent(for: settings.accent) : Color.disabledFill)
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
        .onAppear(perform: load)
        .confirmationDialog("删除这条记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteAndDismiss() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: 子视图

    private func toggleChip(_ label: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Color.onPrimary : Color.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(on ? Color.primaryText : Color.chipFill))
        }
        .buttonStyle(PressableStyle(scale: 0.93))
        .sensoryFeedback(.selection, trigger: isTodo)
    }

    private func photoPreview(_ data: Data) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button {
                photoData = nil
                if let editing { editing.photoData = nil }
            } label: {
                Label("移除", systemImage: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardTint)
        )
    }

    private func voicePreview(_ voice: (fileName: String, duration: TimeInterval)) -> some View {
        Button {
            audio.togglePlay(fileName: voice.fileName, recordId: editing?.id ?? UUID())
        } label: {
            Label(
                String(format: "语音 · %d:%02d", Int(voice.duration) / 60, Int(voice.duration) % 60),
                systemImage: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill"
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.primaryText)
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardTint)
        )
    }

    /// 待办时间设置：两行菜单快捷选择 + 提醒开关
    private var scheduleCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("日期", systemImage: "calendar")
                    .font(.system(size: 15))
                Spacer()
                dayMenu
            }
            .padding(.vertical, 10)

            if showDatePicker {
                DatePicker("", selection: $customDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                    .onChange(of: customDate) { _, value in
                        dueDay = DayPlanner.normalizedDay(value)
                    }
            }

            Divider().padding(.leading, 4)

            HStack {
                Label("时间", systemImage: "clock")
                    .font(.system(size: 15))
                Spacer()
                timeMenu
            }
            .padding(.vertical, 10)

            if showTimePicker {
                DatePicker("", selection: $customTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                    .onChange(of: customTime) { _, value in
                        applyTime(hourMinute: value)
                    }
            }

            Divider().padding(.leading, 4)

            Toggle(isOn: $reminder) {
                Label("到点提醒", systemImage: "bell")
                    .font(.system(size: 15))
            }
            .disabled(dueTime == nil)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardTint)
        )
    }

    @State private var showDatePicker = false
    @State private var showTimePicker = false
    @State private var customDate = Date()
    @State private var customTime = Date()
    @State private var showAtMenu = false

    private var dayMenu: some View {
        Menu {
            Button("某天（不定日期）") { dueDay = nil; showDatePicker = false }
            Button("今天") { dueDay = DayPlanner.normalizedDay(Date()); showDatePicker = false }
            Button("明天") { dueDay = dayOffset(1); showDatePicker = false }
            Button("后天") { dueDay = dayOffset(2); showDatePicker = false }
            Button("下周") { dueDay = dayOffset(7); showDatePicker = false }
            Button("具体日期…") {
                customDate = dueDay ?? Date()
                showDatePicker = true
            }
        } label: {
            menuLabel(dayMenuText, active: dueDay != nil)
        }
    }

    private var dayMenuText: String {
        guard let day = dueDay else { return "某天" }
        let index = DayPlanner.dayIndex(of: day, hour: 0, minute: 0)
        switch index {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        case 7: return "下周"
        default: return DayPlanner.localizedDate(day)
        }
    }

    private var timeMenu: some View {
        Menu {
            Button("无时间") { dueTime = nil; showTimePicker = false }
            ForEach([9, 12, 15, 18, 21], id: \.self) { hour in
                Button(String(format: "%02d:00", hour)) {
                    applyTime(hour: hour, minute: 0)
                    showTimePicker = false
                }
            }
            Button("选择时间…") {
                customTime = dueTime ?? Date()
                showTimePicker = true
            }
        } label: {
            menuLabel(dueTime.map { DayPlanner.hm($0) } ?? "无时间", active: dueTime != nil)
        }
    }

    private func menuLabel(_ text: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Text(text)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(active ? Color.primaryText : Color.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.chipFill))
    }

    private func dayOffset(_ days: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: days, to: DayPlanner.normalizedDay(Date()))
    }

    private func applyTime(hour: Int, minute: Int) {
        let day = dueDay ?? DayPlanner.normalizedDay(Date())
        if dueDay == nil { dueDay = day }
        dueTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private func applyTime(hourMinute: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: hourMinute)
        applyTime(hour: comps.hour ?? 9, minute: comps.minute ?? 0)
    }

    /// 置顶 / 高光
    private var flagCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $isPinned) {
                Label("置顶", systemImage: "pin")
                    .font(.system(size: 15))
            }
            .padding(.vertical, 10)
            Divider().padding(.leading, 4)
            Toggle(isOn: $isHighlighted) {
                Label("高光", systemImage: "sparkles")
                    .font(.system(size: 15))
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardTint)
        )
    }

    // MARK: 数据    // MARK: 数据

    private var effectivePhoto: Data? {
        photoData ?? editing?.photoData
    }

    private var effectiveVoice: (fileName: String, duration: TimeInterval)? {
        if let editing, let file = editing.voiceFileName {
            return (file, editing.voiceDuration)
        }
        if let presetVoice {
            return (presetVoice.fileName, presetVoice.duration)
        }
        return nil
    }

    private var voiceFileName: String? {
        effectiveVoice?.fileName
    }

    private func load() {
        guard let editing, text.isEmpty else {
            if editing == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { textFocused = true }
            }
            return
        }
        text = editing.text
        isTodo = editing.isTodo
        dueDay = editing.dueDay
        dueTime = editing.dueTime
        reminder = editing.wantsReminder
        isPinned = editing.isPinned
        isHighlighted = editing.isHighlighted
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave else { return }

        let time = isTodo ? dueTime : nil
        let wantsReminder = isTodo && reminder && time != nil

        if let editing {
            editing.text = trimmed
            editing.kind = isTodo ? .todo : (editing.photoData != nil ? .photo : (editing.voiceFileName != nil ? .voice : .text))
            editing.dueDay = isTodo ? dueDay : nil
            editing.dueTime = time
            editing.wantsReminder = wantsReminder
            editing.isPinned = isPinned
            editing.isHighlighted = isHighlighted
            if let photoData { editing.photoData = photoData }
            NotificationManager.cancelRecord(editing)
            syncReminder(recordId: editing.id, time: time, wantsReminder: wantsReminder, isDone: editing.isDone)
        } else {
            let kind: Record.Kind = isTodo ? .todo : (presetPhoto != nil ? .photo : (presetVoice != nil ? .voice : .text))
            let record = Record(
                text: trimmed,
                kind: kind,
                isDone: false,
                dueDay: isTodo ? dueDay : nil,
                dueTime: time,
                wantsReminder: wantsReminder,
                isPinned: isPinned,
                isHighlighted: isHighlighted,
                photoData: presetPhoto,
                voiceFileName: presetVoice?.fileName,
                voiceDuration: presetVoice?.duration ?? 0
            )
            context.insert(record)
            syncReminder(recordId: record.id, time: time, wantsReminder: wantsReminder, isDone: false)
        }
        try? context.save()
        saveHaptic.notificationOccurred(.success)
        dismiss()
    }

    private func syncReminder(recordId: UUID, time: Date?, wantsReminder: Bool, isDone: Bool) {
        NotificationManager.syncRecord(id: recordId, title: text, time: time, wantsReminder: wantsReminder, isDone: isDone, enabled: settings.remindersEnabled)
    }

    private func deleteAndDismiss() {
        guard let editing else { return }
        NotificationManager.cancelRecord(editing)
        if let file = editing.voiceFileName {
            AudioHelper.shared.deleteVoiceFile(file)
        }
        context.delete(editing)
        try? context.save()
        dismiss()
    }
}
