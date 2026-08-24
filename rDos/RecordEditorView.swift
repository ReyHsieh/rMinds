import SwiftUI
import SwiftData
import PhotosUI

/// 记录编辑器：新建（照片/语音草稿）或编辑既有记录。
/// 待办可设置日期时间与提醒。
struct RecordEditorView: View {
    enum DayChoice: Hashable {
        case none, today, tomorrow, pick
    }

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
    @State private var dayChoice: DayChoice = .none
    @State private var pickDate = Date()
    @State private var hasTime = false
    @State private var timeDate = Date()
    @State private var reminder = true
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
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.secondaryText.opacity(0.25))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

            TextField(isTodo ? "待办内容" : "记录点什么…", text: $text, axis: .vertical)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primaryText)
                .focused($textFocused)
                .submitLabel(.done)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.cardTint)
                )

            HStack(spacing: 8) {
                toggleChip("待办", icon: "checklist", on: isTodo) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isTodo.toggle() }
                }
                if photoData != nil || editing?.photoData != nil {
                    toggleChip("含照片", icon: "photo", on: true) {}
                }
                if voiceFileName != nil {
                    toggleChip("语音", icon: "waveform", on: true) {}
                }
                Spacer()
                if !previewTags.isEmpty {
                    ForEach(previewTags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.badgeBackground))
                    }
                }
            }

            if let data = effectivePhoto {
                photoPreview(data)
            }

            if let voice = effectiveVoice {
                voicePreview(voice)
            }

            if isTodo {
                dayChips
                if dayChoice != .none {
                    timeCard
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

    private var dayChips: some View {
        HStack(spacing: 8) {
            dayChip("无日期", .none)
            dayChip("今天", .today)
            dayChip("明天", .tomorrow)
            dayChip("选日期", .pick)
        }
    }

    private func dayChip(_ label: String, _ value: DayChoice) -> some View {
        let selected = dayChoice == value
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { dayChoice = value }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.onPrimary : Color.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Color.primaryText : Color.chipFill))
        }
        .buttonStyle(PressableStyle(scale: 0.93))
        .sensoryFeedback(.selection, trigger: dayChoice)
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 12, weight: .semibold))
                Text("时间与提醒").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.secondaryText)
            Toggle("添加时间", isOn: $hasTime)
                .font(.system(size: 15))
            if hasTime {
                DatePicker("", selection: $timeDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Toggle("到点提醒", isOn: $reminder)
                    .font(.system(size: 15))
            }
            if dayChoice == .pick {
                DatePicker("日期", selection: $pickDate, displayedComponents: .date)
                    .font(.system(size: 15))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardTint)
        )
    }

    // MARK: 数据

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

    private var previewTags: [String] {
        Record.parseTags(from: text)
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
        if let day = editing.dueDay {
            let index = DayPlanner.dayIndex(of: day, hour: settings.dayStartHour, minute: settings.dayStartMinute)
            switch index {
            case 0: dayChoice = .today
            case 1: dayChoice = .tomorrow
            default:
                dayChoice = .pick
                pickDate = day
            }
        } else {
            dayChoice = .none
        }
        hasTime = editing.dueTime != nil
        if let time = editing.dueTime {
            timeDate = time
        } else if let day = resolvedDay,
                  let nine = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) {
            timeDate = nine
        }
        reminder = editing.wantsReminder
    }

    private var resolvedDay: Date? {
        switch dayChoice {
        case .none: return nil
        case .today: return DayPlanner.normalizedDay(Date())
        case .tomorrow: return DayPlanner.normalizedDay(Date().addingTimeInterval(86_400))
        case .pick: return DayPlanner.normalizedDay(pickDate)
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave else { return }

        let day = resolvedDay
        var time: Date? = nil
        if hasTime, let day {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: timeDate)
            time = Calendar.current.date(
                bySettingHour: comps.hour ?? 9,
                minute: comps.minute ?? 0,
                second: 0,
                of: day
            )
        }
        let wantsReminder = isTodo && hasTime && reminder && time != nil

        if let editing {
            editing.text = trimmed
            editing.kind = isTodo ? .todo : (editing.photoData != nil ? .photo : (editing.voiceFileName != nil ? .voice : .text))
            editing.dueDay = day
            editing.dueTime = time
            editing.wantsReminder = wantsReminder
            if let photoData { editing.photoData = photoData }
            NotificationManager.cancelRecord(editing)
            syncReminder(recordId: editing.id, time: time, wantsReminder: wantsReminder, isDone: editing.isDone)
        } else {
            let kind: Record.Kind = isTodo ? .todo : (presetPhoto != nil ? .photo : (presetVoice != nil ? .voice : .text))
            let record = Record(
                text: trimmed,
                kind: kind,
                isDone: false,
                dueDay: day,
                dueTime: time,
                wantsReminder: wantsReminder,
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
