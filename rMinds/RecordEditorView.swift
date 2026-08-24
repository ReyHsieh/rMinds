import SwiftUI
import SwiftData
import PhotosUI

/// 记录编辑器：编辑既有记录（新建走输入栏组合编辑器，直接入流）。
/// 待办可设置日期时间与提醒；可增删图片与语音附件。
struct RecordEditorView: View {
    let editing: Record

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var text = ""
    @State private var isTodo = false
    @State private var dueDay: Date? = nil
    @State private var dueTime: Date? = nil
    @State private var reminder = true
    @State private var isPinned = false
    @State private var photoData: Data?
    @State private var confirmDelete = false
    @FocusState private var textFocused: Bool

    private let saveHaptic = UINotificationFeedbackGenerator()
    private var audio = AudioHelper.shared

    private var canSave: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isTodo { return hasText }
        return hasText || effectivePhoto != nil || effectiveVoice != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Capsule()
                    .fill(Color.secondaryText.opacity(0.25))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)

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
                    .onChange(of: editorPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.downscaled(maxDimension: 1600, quality: 0.78) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        photoData = jpeg
                    }
                }
                editorPhotoItem = nil
            }
        }
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

            if recording {
                editorRecordingBar
            } else if effectivePhoto == nil || effectiveVoice == nil {
                HStack(spacing: 8) {
                    if effectivePhoto == nil {
                        PhotosPicker(selection: $editorPhotoItem, matching: .images) {
                            chipLabel("添加图片", icon: "photo")
                        }
                        .buttonStyle(PressableStyle(scale: 0.93))
                    }
                    if effectiveVoice == nil {
                        Button {
                            startEditorRecording()
                        } label: {
                            chipLabel("录语音", icon: "mic.fill")
                        }
                        .buttonStyle(PressableStyle(scale: 0.93))
                    }
                }
            }

            if isTodo {
                scheduleCard
            }

                flagCard

            quoteCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
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
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(
                Rectangle()
                    .fill(Color.appBackground)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.5),
                                .init(color: .black, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .padding(.horizontal, 20)
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
            VStack(spacing: 8) {
                PhotosPicker(selection: $editorPhotoItem, matching: .images) {
                    Label("更换", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                }
                .buttonStyle(.plain)
                Button {
                    photoData = nil
                    editing.photoData = nil
                } label: {
                    Label("移除", systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardTint)
        )
    }

    @ViewBuilder
    private func voicePreview(_ voice: (fileName: String, duration: TimeInterval)) -> some View {
        Button {
            audio.togglePlay(fileName: voice.fileName, recordId: editing.id)
        } label: {
            Label(
                String(format: "语音 · %d:%02d", Int(voice.duration) / 60, Int(voice.duration) % 60),
                systemImage: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill"
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.primaryText)
        }
        .buttonStyle(.plain)
        Spacer()
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                if let old = editing.voiceFileName {
                    AudioHelper.shared.deleteVoiceFile(old)
                }
                recordedVoice = nil
                editing.voiceFileName = nil
                editing.voiceDuration = 0
            }
        } label: {
            Label("移除", systemImage: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
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
    @State private var recordedVoice: (fileName: String, duration: TimeInterval)?
    @State private var recording = false
    @State private var recElapsed: TimeInterval = 0
    @State private var recPulse = false
    @State private var editorPhotoItem: PhotosPickerItem?

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
        switch DayPlanner.naturalDayIndex(of: day) {
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

    /// 置顶
    private var flagCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $isPinned) {
                Label("置顶", systemImage: "pin")
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

    private var editorRecordingBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .scaleEffect(recPulse ? 1.25 : 0.85)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: recPulse)
            Text(String(format: "%d:%02d", Int(recElapsed) / 60, Int(recElapsed) % 60))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.primaryText)
            Spacer()
            Button {
                _ = audio.stopRecording(cancel: true)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { recording = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.chipFill))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            Button {
                if let result = audio.stopRecording(cancel: false) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        recordedVoice = result
                        recording = false
                    }
                } else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { recording = false }
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.onPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.accent(for: settings.accent)))
            }
            .buttonStyle(PressableStyle(scale: 0.88))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardTint)
        )
    }

    private func startEditorRecording() {
        audio.startRecording()
        recording = true
        recPulse = true
        textFocused = false
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if !recording {
                timer.invalidate()
                return
            }
            recElapsed = audio.elapsed
            if recElapsed >= 30 {
                timer.invalidate()
                if let result = audio.stopRecording(cancel: false) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        recordedVoice = result
                        recording = false
                    }
                } else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { recording = false }
                }
                return
            }
            if audio.micPermissionDenied {
                timer.invalidate()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { recording = false }
            }
        }
    }

    private func chipLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.chipFill))
    }

    // MARK: 引用

    @State private var showQuotePicker = false
    @State private var selectedQuoteID: UUID?

    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening").font(.system(size: 12, weight: .semibold))
                Text("引用").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.secondaryText)

            if let quoted = resolvedQuote {
                HStack(spacing: 8) {
                    Capsule().fill(Color.secondaryText.opacity(0.4)).frame(width: 2.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(QuotePickerSheet.kindLabel(quoted))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.secondaryText)
                        Text(quoted.text.isEmpty ? "—" : quoted.text)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.badgeBackground))
            }

            HStack(spacing: 8) {
                Button {
                    showQuotePicker = true
                } label: {
                    Label(resolvedQuote == nil ? "添加引用" : "更换引用", systemImage: "quote.opening")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.chipFill))
                }
                .buttonStyle(PressableStyle(scale: 0.93))

                if resolvedQuote != nil {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedQuoteID = nil
                        }
                    } label: {
                        Label("移除", systemImage: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardTint)
        )
        .sheet(isPresented: $showQuotePicker) {
            QuotePickerSheet(records: allRecords) { picked in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    selectedQuoteID = picked.id
                }
                showQuotePicker = false
            }
        }
    }

    @Query private var allRecords: [Record]

    private var resolvedQuote: Record? {
        guard let id = selectedQuoteID ?? editing.quoteID else { return nil }
        return allRecords.first { $0.id == id && $0.deletedAt == nil }
    }

    // MARK: 数据

    private var effectivePhoto: Data? {
        photoData ?? editing.photoData
    }

    private var effectiveVoice: (fileName: String, duration: TimeInterval)? {
        if let recordedVoice { return recordedVoice }
        if let file = editing.voiceFileName {
            return (file, editing.voiceDuration)
        }
        return nil
    }

    private var voiceFileName: String? {
        effectiveVoice?.fileName
    }

    private func load() {
        guard text.isEmpty else { return }
        text = editing.text
        isTodo = editing.isTodo
        dueDay = editing.dueDay
        dueTime = editing.dueTime
        reminder = editing.wantsReminder
        isPinned = editing.isPinned
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave else { return }

        let time = isTodo ? dueTime : nil
        let wantsReminder = isTodo && reminder && time != nil

        let hasPhoto = effectivePhoto != nil
        let hasVoice = effectiveVoice != nil
        if let recordedVoice {
            if let old = editing.voiceFileName, old != recordedVoice.fileName {
                AudioHelper.shared.deleteVoiceFile(old)
            }
            editing.voiceFileName = recordedVoice.fileName
            editing.voiceDuration = recordedVoice.duration
        }
        editing.text = trimmed
        editing.kind = isTodo ? .todo : (hasPhoto ? .photo : (hasVoice ? .voice : .text))
        editing.dueDay = isTodo ? dueDay : nil
        editing.dueTime = time
        editing.wantsReminder = wantsReminder
        editing.isPinned = isPinned
        editing.quoteID = selectedQuoteID
        if let photoData { editing.photoData = photoData }
        NotificationManager.cancelRecord(editing)
        syncReminder(recordId: editing.id, time: time, wantsReminder: wantsReminder, isDone: editing.isDone)
        try? context.save()
        saveHaptic.notificationOccurred(.success)
        dismiss()
    }

    private func syncReminder(recordId: UUID, time: Date?, wantsReminder: Bool, isDone: Bool) {
        NotificationManager.syncRecord(id: recordId, title: text, time: time, wantsReminder: wantsReminder, isDone: isDone, enabled: settings.remindersEnabled)
    }

    private func deleteAndDismiss() {
        NotificationManager.cancelRecord(editing)
        withAnimation { editing.deletedAt = Date() }   // 软删除，可在设置→最近删除恢复
        try? context.save()
        dismiss()
    }
}
