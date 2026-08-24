import SwiftUI
import PhotosUI

/// 底部输入栏（iMessage 式组合编辑器）：
/// 文字可留空；图片/语音以暂存附件形式贴在输入栏上方；@ 设为待办（今日/明日/某天/具体日期）。
/// 发送时合并为一条记录，直接入流，不经过编辑页。
/// 输入栏一次发送的完整内容
struct OutgoingDraft {
    var text: String
    var dueDay: Date?
    var isTodo: Bool
    var photo: Data?
    var voice: (fileName: String, duration: TimeInterval)?
    var quoteID: UUID?
}

struct RecordInputBar: View {
    enum PendingTodo: Equatable {
        case none
        case someday
        case day(Date)
    }

    var onSend: (OutgoingDraft) -> Void
    @Binding var pendingQuote: Record?

    @Environment(AppSettings.self) private var settings
    @State private var draft = ""
    @State private var pendingTodo: PendingTodo = .none
    @State private var pendingPhoto: Data?
    @State private var pendingVoice: (fileName: String, duration: TimeInterval)?
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
                    onPickDay: { date in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            pendingTodo = .day(date)
                            showAtMenu = false
                            showAtCalendar = false
                        }
                        focused = true
                    },
                    onSomeday: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            pendingTodo = .someday
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
                            pendingTodo = .day(DayPlanner.normalizedDay(atCalendarDate))
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
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showAtCalendar = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.secondaryText)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.badgeBackground))
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.chipFill))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 引用条
            if let quote = pendingQuote, quote.deletedAt == nil {
                HStack(spacing: 8) {
                    Capsule().fill(Color.secondaryText.opacity(0.4)).frame(width: 2.5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("引用")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.secondaryText)
                        Text(quote.text.isEmpty ? "—" : quote.text)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            pendingQuote = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.badgeBackground)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 暂存附件区（iMessage 式）
            if pendingPhoto != nil || pendingVoice != nil {
                HStack(spacing: 10) {
                    if let data = pendingPhoto, let image = UIImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            removeButton {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    pendingPhoto = nil
                                }
                            }
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    if let voice = pendingVoice {
                        ZStack(alignment: .topTrailing) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(String(format: "%d:%02d", Int(voice.duration) / 60, Int(voice.duration) % 60))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(Color.primaryText)
                            .frame(width: 76, height: 64)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.chipFill))
                            removeButton {
                                if let file = pendingVoice?.fileName {
                                    AudioHelper.shared.deleteVoiceFile(file)
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    pendingVoice = nil
                                }
                            }
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
            }

            if pendingTodo != .none {
                todoChip
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
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pendingTodo)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pendingPhoto)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pendingVoice == nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pendingQuote?.id)
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        pendingPhoto = jpeg
                    }
                    focused = true
                }
                photoItem = nil
            }
        }
        .onChange(of: draft) { _, new in
            handleDraftChange(new)
        }
        .onDisappear {
            if recording {
                _ = audio.stopRecording(cancel: true)
                recording = false
            }
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.secondaryText, Color.appBackground)
        }
        .buttonStyle(.plain)
        .offset(x: 6, y: -6)
    }

    // MARK: 常规输入栏

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            InputTextEditor(
                text: $draft,
                placeholder: placeholder,
                focused: $focused,
                onChange: { handleDraftChange($0) }
            )

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
                Image(systemName: pendingTodo == .none ? "arrow.up" : "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? Color.onPrimary : Color.secondaryText)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(canSend ? Color.accent(for: settings.accent) : Color.disabledFill))
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var placeholder: String {
        if pendingTodo != .none { return "添加待办…" }
        if pendingPhoto != nil || pendingVoice != nil { return "说点什么…（可留空）" }
        return "记录此刻…（@ 待办）"
    }

    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || pendingPhoto != nil || pendingVoice != nil
    }

    /// 待办胶囊：点按改期/改某天，×取消待办（回到普通记录）
    private var todoChip: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showAtMenu = true
                }
            } label: {
                Label(todoChipText, systemImage: pendingTodo == .someday ? "sparkles" : "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.onPrimary)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    pendingTodo = .none
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.onPrimary.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.accent(for: settings.accent)))
    }

    private var todoChipText: String {
        switch pendingTodo {
        case .none: return ""
        case .someday: return "某天待办"
        case .day(let date):
            switch DayPlanner.naturalDayIndex(of: date) {
            case 0: return "今日待办"
            case 1: return "明日待办"
            default: return DayPlanner.localizedDate(date)
            }
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
            // 30 秒上限：自动完成
            if elapsed >= 30 {
                timer.invalidate()
                finishVoice()
                return
            }
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                pendingVoice = result
            }
            focused = true
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            recording = false
        }
    }

    private func handleDraftChange(_ new: String) {
        // 输入 @ 触发日期选择，并把 @ 从草稿移除
        if new.hasSuffix("@") {
            draft = String(new.dropLast())
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showAtMenu = true
                showAtCalendar = false
            }
        }
    }

    private func send() {
        guard canSend else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTodo = pendingTodo != .none
        let dueDay: Date? = if case .day(let date) = pendingTodo { date } else { nil }
        let draft = OutgoingDraft(
            text: trimmed,
            dueDay: dueDay,
            isTodo: isTodo,
            photo: pendingPhoto,
            voice: pendingVoice,
            quoteID: (pendingQuote?.deletedAt == nil ? pendingQuote?.id : nil)
        )
        onSend(draft)
        self.draft = ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            pendingTodo = .none
            pendingPhoto = nil
            pendingVoice = nil
            pendingQuote = nil
            showAtMenu = false
            showAtCalendar = false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// 多行输入（回车=换行，不触发发送；发送走独立按钮/⌘↩）。
/// iMessage 式增高：短内容按真实内容高度生长（隐藏镜像文本精确测量，
/// 不做字符估算），到 5 行封顶后固定高度、内部滚动并自动跟随光标行
/// （UITextView 原生保持光标可见，选中行切换同样跟随）。
struct InputTextEditor: View {
    @Binding var text: String
    var placeholder: String
    var focused: FocusState<Bool>.Binding
    var onChange: (String) -> Void = { _ in }

    @State private var measuredHeight: CGFloat = 22

    private var lineHeight: CGFloat { ceil(FS.s(16) * 1.35) }
    private var maxLines: Int { 5 }
    private var visibleHeight: CGFloat {
        min(max(measuredHeight, lineHeight), lineHeight * CGFloat(maxLines))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: FS.s(16), weight: .medium))
                .foregroundStyle(Color.primaryText)
                .scrollContentBackground(.hidden)
                .frame(height: visibleHeight)
                .frame(maxWidth: .infinity)
                .focused(focused)
                .onChange(of: text) { _, new in
                    onChange(new)
                }
                // 内省清零 UITextView 内边距：文字/光标精确落在原点
                .background(EditorInsetRemover())

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: FS.s(16), weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(minWidth: 120)
        // 镜像测量层：挂在 overlay 不参与布局，仅报告内容真实高度
        .background(
            // 镜像测量层：报告内容真实高度（补偿外层 padding，与编辑区对齐）
            Color.clear
                .frame(height: 0)
                .overlay(alignment: .topLeading) {
                    Text(text.isEmpty ? " " : text)
                        .font(.system(size: FS.s(16), weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            measuredHeight = height
                        }
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, -4)
                .padding(.top, -8)
        )
    }
}

/// 找到 TextEditor 底层的 UITextView 并清零其内边距
/// （textContainerInset + lineFragmentPadding≈5pt，SwiftUI 无 API 可控，
///  是光标与占位符错位的根因；社区标准解法：内省后置零）。
struct EditorInsetRemover: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async { configure(from: view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private func configure(from view: UIView) {
        guard let superview = view.superview else { return }
        if let textView = superview as? UITextView {
            apply(to: textView)
            return
        }
        for subview in superview.subviews {
            if let textView = findTextView(in: subview) {
                apply(to: textView)
                return
            }
        }
        configure(from: superview)
    }

    private func findTextView(in view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        for subview in view.subviews {
            if let textView = findTextView(in: subview) { return textView }
        }
        return nil
    }

    private func apply(to textView: UITextView) {
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
    }
}

/// @ 触发的待办快捷菜单（输入栏与编辑器共用）：今日 / 明日 / 某天 / 具体日期…
struct AtDateMenu: View {
    var onPickDay: (Date) -> Void
    var onSomeday: () -> Void
    var onCustom: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AtMenuButton(title: "今日") {
                onPickDay(DayPlanner.normalizedDay(Date()))
            }
            AtMenuButton(title: "明日") {
                onPickDay(DayPlanner.normalizedDay(Date().addingTimeInterval(86_400)))
            }
            AtMenuButton(title: "某天") {
                onSomeday()
            }
            AtMenuButton(title: "具体日期…", filled: false) {
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
