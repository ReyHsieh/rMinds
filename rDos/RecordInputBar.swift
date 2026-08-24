import SwiftUI
import PhotosUI

/// 底部输入栏：文字即时入流；输入 @ 弹出日期选择（自动转待办）；选照片（进编辑器）；按住录语音。
struct RecordInputBar: View {
    var onSend: (String, Date?) -> Void
    var onPickPhoto: (Data) -> Void
    var onVoiceDone: (String, TimeInterval) -> Void

    @Environment(AppSettings.self) private var settings
    @State private var draft = ""
    @State private var pendingTodoDate: Date?
    @State private var showAtMenu = false
    @State private var showAtCalendar = false
    @State private var atCalendarDate = Date()
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var focused: Bool

    @State private var recording = false
    @State private var elapsed: TimeInterval = 0
    @State private var pulse = false
    private var audio = AudioHelper.shared

    var body: some View {
        VStack(spacing: 8) {
            if showAtMenu {
                AtDateMenu(
                    onPick: { date in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            pendingTodoDate = date
                            showAtMenu = false
                            showAtCalendar = false
                        }
                        focused = true
                    },
                    onCustom: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showAtMenu = false
                            showAtCalendar = true
                        }
                    },
                    onCancel: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showAtMenu = false
                        }
                        focused = true
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if showAtCalendar {
                HStack(spacing: 10) {
                    DatePicker(
                        "",
                        selection: $atCalendarDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Color.accent(for: settings.accent))
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            pendingTodoDate = DayPlanner.normalizedDay(atCalendarDate)
                            showAtCalendar = false
                        }
                        focused = true
                    } label: {
                        Text("确定")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.onPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.accent(for: settings.accent)))
                    }
                    .buttonStyle(PressableStyle(scale: 0.93))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.chipFill))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let date = pendingTodoDate {
                todoChip(date)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if recording {
                recordingBar
            } else {
                inputBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showAtMenu)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showAtCalendar)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pendingTodoDate)
        .background(
            Rectangle()
                .fill(Color.appBackground)
                .ignoresSafeArea(edges: .bottom)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.35),
                            .init(color: .black, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.downscaled(maxDimension: 1600, quality: 0.78) {
                    onPickPhoto(jpeg)
                }
                photoItem = nil
            }
        }
        .onChange(of: draft) { _, new in
            // 输入 @ 触发日期选择，并把 @ 从草稿移除
            if new.hasSuffix("@") {
                draft = String(new.dropLast())
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showAtMenu = true
                    showAtCalendar = false
                }
            }
        }
        .onDisappear {
            if recording {
                _ = audio.stopRecording(cancel: true)
                recording = false
            }
        }
    }

    // MARK: 常规输入栏

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(pendingTodoDate == nil ? "记录此刻…（@ 设为待办）" : "添加待办…", text: $draft, axis: .vertical)
                .font(.system(size: FS.s(16), weight: .medium))
                .foregroundStyle(Color.primaryText)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.chipFill))
            }
            .buttonStyle(PressableStyle(scale: 0.9))

            holdToRecordButton

            Button(action: send) {
                Image(systemName: pendingTodoDate == nil ? "arrow.up" : "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? Color.onPrimary : Color.secondaryText)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(canSend ? Color.accent(for: settings.accent) : Color.disabledFill))
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .disabled(!canSend)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 待办日期胶囊：点按改期，×清除（回到普通记录）
    private func todoChip(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showAtMenu = true
                }
            } label: {
                Label(todoChipText(date), systemImage: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.onPrimary)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    pendingTodoDate = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.onPrimary.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.accent(for: settings.accent)))
    }

    private func todoChipText(_ date: Date) -> String {
        let index = DayPlanner.dayIndex(of: date, hour: settings.dayStartHour, minute: settings.dayStartMinute)
        switch index {
        case 0: return "今日待办"
        case 1: return "明日待办"
        default: return DayPlanner.localizedDate(date)
        }
    }

    /// 按住录音：按下开始，松开由录音条确认（<0.5s 自动取消）
    private var holdToRecordButton: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
            .frame(width: 38, height: 38)
            .background(Circle().fill(Color.chipFill))
            .contentShape(Circle())
            .onLongPressGesture(
                minimumDuration: 0.25,
                maximumDistance: 40,
                perform: {},
                onPressingChanged: { pressing in
                    if pressing {
                        beginVoice()
                    }
                }
            )
    }

    // MARK: 录音条

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.25 : 0.85)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)

            Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.primaryText)

            Spacer()

            Button {
                cancelVoice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.chipFill))
            }
            .buttonStyle(PressableStyle(scale: 0.9))

            Button {
                finishVoice()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.onPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.accent(for: settings.accent)))
            }
            .buttonStyle(PressableStyle(scale: 0.88))
        }
    }

    // MARK: 录音控制

    private func beginVoice() {
        audio.startRecording()
        recording = true
        pulse = true
        focused = false
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if !recording {
                timer.invalidate()
                return
            }
            elapsed = audio.elapsed
            // 权限被拒时自动收起录音条（权限弹窗期间会等待结果）
            if audio.micPermissionDenied {
                timer.invalidate()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    recording = false
                }
            }
        }
    }

    private func cancelVoice() {
        _ = audio.stopRecording(cancel: true)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            recording = false
        }
    }

    private func finishVoice() {
        if let result = audio.stopRecording(cancel: false) {
            onVoiceDone(result.0, result.1)
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            recording = false
        }
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed, pendingTodoDate)
        draft = ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            pendingTodoDate = nil
            showAtMenu = false
            showAtCalendar = false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// @ 触发的日期快捷菜单（输入栏与编辑器共用）
struct AtDateMenu: View {
    var onPick: (Date?) -> Void
    var onCustom: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AtMenuButton(title: "今日") {
                onPick(DayPlanner.normalizedDay(Date()))
            }
            AtMenuButton(title: "明日") {
                onPick(DayPlanner.normalizedDay(Date().addingTimeInterval(86_400)))
            }
            AtMenuButton(title: "某日…", filled: false) {
                onCustom()
            }
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.secondaryText)
            }
            .buttonStyle(.plain)
        }
    }
}

struct AtMenuButton: View {
    @Environment(AppSettings.self) private var settings
    let title: String
    var filled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filled ? Color.onPrimary : Color.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(filled ? Color.accent(for: settings.accent) : Color.chipFill)
                )
        }
        .buttonStyle(PressableStyle(scale: 0.93))
        .sensoryFeedback(.selection, trigger: title)
    }
}

extension UIImage {
    /// 等比缩小并压缩为 JPEG Data
    func downscaled(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let largest = max(size.width, size.height)
        let scale = largest > maxDimension ? maxDimension / largest : 1
        if scale < 1 {
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resized = renderer.image { _ in
                draw(in: CGRect(origin: .zero, size: newSize))
            }
            return resized.jpegData(compressionQuality: quality)
        }
        return jpegData(compressionQuality: quality)
    }
}
