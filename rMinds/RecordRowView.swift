import SwiftUI
import SwiftData

/// 图片解码缓存：避免滑动过程中每帧重建/重解码 UIImage
enum RecordImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for data: Data, key: String) -> UIImage? {
        let k = key as NSString
        if let cached = cache.object(forKey: k) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: k)
        return image
    }
}

enum RowContext {
    case active
    case archive
}

/// 时间线上的一条记录。
/// 手势矩阵：单击=编辑；长按=引用；右滑(leading)=置顶+删除；左滑(trailing)=待办完成。
struct RecordRowView: View {
    let record: Record
    var actions: RecordActions
    var context: RowContext = .active
    var frameKey: String? = nil

    @Environment(AppSettings.self) private var settings
    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var suppressTap = false
    @State private var horizontalLock = false
    @State private var panStart: CGPoint?
    @State private var showPhoto = false

    private var audio = AudioHelper.shared

    private let actionSize: CGFloat = 44
    private let actionGap: CGFloat = 10
    private let openThreshold: CGFloat = 48
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    /// 右滑（leading）：置顶 + 删除
    private var leadingWidth: CGFloat { actionSize * 2 + actionGap }
    /// 左滑（trailing）：待办完成（非待办为 0，不可划）
    private var trailingWidth: CGFloat { record.isTodo ? actionSize : 0 }

    var body: some View {
        ZStack {
            actionsLayer
            content
                .offset(x: offset)
                .gesture(panGesture)
                .gesture(
                    LongPressRepresentable {
                        haptic.impactOccurred()
                        actions.onQuote(record)
                    }
                )
        }
        .padding(.vertical, 5)
    }

    // MARK: 内容

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(DayPlanner.hm(record.createdAt))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondaryText)
                .frame(width: 36, alignment: .leading)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 7) {
                if let quoted = quotedRecord {
                    quotePreview(quoted)
                }
                if record.isPinned {
                    Label("已置顶", systemImage: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                }
                if record.isTodo {
                    todoBody
                } else if !record.text.isEmpty {
                    textBody
                }
                if record.photoData != nil {
                    photoBody
                }
                if record.voiceFileName != nil {
                    voiceBody
                    if let transcript = record.transcript, !transcript.isEmpty {
                        transcriptBody(transcript)
                    }
                }
            }
            .padding(.top, startsWithVoice ? -3 : 0)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
        .fullScreenCover(isPresented: $showPhoto) {
            PhotoViewer(photoData: record.photoData)
        }
    }

    private var textBody: some View {
        Text(record.text)
            .font(.system(size: FS.s(16), weight: .medium))
            .foregroundStyle(Color.primaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todoBody: some View {
        HStack(alignment: .top, spacing: 11) {
            checkbox
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    actions.onToggleDone(record)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.text)
                    .font(.system(size: FS.s(16), weight: .medium))
                    .foregroundStyle(record.isDone ? Color.secondaryText : Color.primaryText)
                    .strikethrough(record.isDone, color: Color.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.25), value: record.isDone)
                if let badge = dueBadge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.badgeBackground))
                }
            }
        }
    }

    private var photoBody: some View {
        Group {
            if let data = record.photoData,
               let image = RecordImageCache.image(for: data, key: record.id.uuidString) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: min(220, image.size.height * (340 / max(1, image.size.width))))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .onTapGesture {
                        if !suppressTap, abs(offset) < 2 { showPhoto = true }
                    }
            }
        }
    }

    /// 胶囊宽度随语音时长伸缩（30s 封顶 → 不超过一行）
    private var voiceBubbleWidth: CGFloat {
        max(160, min(300, 96 + record.voiceDuration * 7))
    }

    private var voiceBody: some View {
        HStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: audio.isPlaying && audio.playingId == record.id ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.primaryText)
                HStack(spacing: 2) {
                    ForEach(0..<14, id: \.self) { i in
                        Capsule()
                            .fill(Color.primaryText.opacity(0.55))
                            .frame(width: 2.5, height: CGFloat([9, 15, 7, 18, 12, 20, 8, 14, 10, 17, 6, 13, 9, 16][i]))
                    }
                }
                Text(String(format: "%d:%02d", Int(record.voiceDuration) / 60, Int(record.voiceDuration) % 60))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(width: voiceBubbleWidth, alignment: .leading)
            .background(Capsule().fill(Color.cardTint))
            .contentShape(Capsule())
            .onTapGesture {
                guard let file = record.voiceFileName else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audio.togglePlay(fileName: file, recordId: record.id)
            }

            if record.transcript == nil {
                transcribeButton
            }
        }
    }

    /// 语音转文字（Apple Speech，优先设备端）
    @State private var transcribing = false

    private var transcribeButton: some View {
        Group {
            if transcribing {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        transcribeVoice()
                    }
            }
        }
        .foregroundStyle(Color.secondaryText)
        .background(Circle().fill(Color.badgeBackground))
        .accessibilityLabel(transcribing ? "转写中" : "转文字")
    }

    private func transcribeVoice() {
        guard let file = record.voiceFileName else { return }
        transcribing = true
        Task {
            defer { transcribing = false }
            guard await SpeechTranscriber.requestAuthorization() else { return }
            guard let url = AudioHelper.shared.urlIfExists(file) else { return }
            if let text = try? await SpeechTranscriber.transcribe(fileURL: url) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        record.transcript = trimmed
                    }
                    try? record.modelContext?.save()
                }
            }
        }
    }

    /// 转写文本展示 + 收起
    private func transcriptBody(_ transcript: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("转写：\(transcript)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    record.transcript = nil
                }
                try? record.modelContext?.save()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondaryText.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.badgeBackground)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var checkbox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(record.isDone ? Color.accent(for: settings.accent) : Color.chipFill)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(record.isDone ? Color.clear : Color.checkboxBorder, lineWidth: 1.5)
            if record.isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.onPrimary)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: 22, height: 22)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: record.isDone)
    }

    private var dueBadge: String? {
        guard let day = record.dueDay else { return nil }
        switch DayPlanner.naturalDayIndex(of: day) {
        case 0: return hasTime ? "今天 · \(timeText)" : "今天"
        case 1: return hasTime ? "明天 · \(timeText)" : "明天"
        default:
            var label = DayPlanner.localizedDate(day)
            if hasTime { label += " · \(timeText)" }
            return label
        }
    }

    private var hasTime: Bool { record.dueTime != nil }
    private var timeText: String { record.dueTime.map { DayPlanner.hm($0) } ?? "" }

    // MARK: 引用

    private var quotedRecord: Record? {
        guard let quoteID = record.quoteID else { return nil }
        let quoted = actions.quoteProvider(quoteID)
        guard let quoted, quoted.deletedAt == nil else { return nil }
        return quoted
    }

    private func quotePreview(_ quoted: Record) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.secondaryText.opacity(0.4))
                .frame(width: 2.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(quoteKindLabel(quoted))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                Text(quoted.text.isEmpty ? "—" : quoted.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.badgeBackground)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            actions.onQuoteTap(quoted)
        }
    }

    private func quoteKindLabel(_ quoted: Record) -> String {
        let time = DayPlanner.hm(quoted.createdAt)
        switch quoted.kind {
        case .text: return "引用 · \(time)"
        case .todo: return "引用待办 · \(time)"
        case .photo: return "引用图片 · \(time)"
        case .voice: return "引用语音 · \(time)"
        }
    }

    private var startsWithVoice: Bool {
        !record.isTodo && record.text.isEmpty && record.photoData == nil && record.voiceFileName != nil
    }

    // MARK: 滑动操作层：右滑=置顶+删除；左滑=完成（待办）

    private var actionsLayer: some View {
        HStack(spacing: actionGap) {
            Button {
                close()
                haptic.impactOccurred()
                actions.onTogglePin(record)
            } label: {
                actionIcon(
                    systemName: record.isPinned ? "pin.slash" : "pin",
                    background: Color.chipFill,
                    foreground: Color.primaryText
                )
            }
            .buttonStyle(.plain)
            .opacity(leadingProgress)
            .scaleEffect(0.7 + 0.3 * leadingProgress)

            Button {
                close()
                haptic.impactOccurred()
                actions.onDelete(record)
            } label: {
                actionIcon(
                    systemName: "trash",
                    background: Color.chipFill,
                    foreground: .red
                )
            }
            .buttonStyle(.plain)
            .opacity(leadingProgress)
            .scaleEffect(0.7 + 0.3 * leadingProgress)

            Spacer(minLength: 0)

            if record.isTodo {
                Button {
                    close()
                    haptic.impactOccurred()
                    actions.onToggleDone(record)
                } label: {
                    actionIcon(
                        systemName: record.isDone ? "arrow.uturn.backward" : "checkmark",
                        background: Color.accent(for: settings.accent),
                        foreground: Color.onPrimary
                    )
                }
                .buttonStyle(.plain)
                .opacity(trailingProgress)
                .scaleEffect(0.7 + 0.3 * trailingProgress)
            }
        }
        .padding(.horizontal, 2)
    }

    private func actionIcon(systemName: String, background: Color, foreground: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: actionSize, height: actionSize)
            .background(Circle().fill(background))
    }

    private var leadingProgress: CGFloat {
        min(1, max(0, offset / leadingWidth))
    }

    private var trailingProgress: CGFloat {
        min(1, max(0, -offset / max(1, trailingWidth)))
    }

    // MARK: 平移手势（原生，方向锁定）

    private var panGesture: PanGesture {
        PanGesture(
            onBegan: { location in
                panStart = location
                horizontalLock = false
            },
            onChanged: { location in
                guard let start = panStart else { return }
                let width = location.x - start.x
                let height = location.y - start.y
                if abs(width) > 8 || abs(height) > 8 {
                    suppressTap = true
                }
                if !horizontalLock {
                    if abs(width) > 14 && abs(width) > abs(height) * 1.2 {
                        horizontalLock = true
                        isDragging = true
                        dragStartOffset = offset
                    } else {
                        return
                    }
                }
                offset = min(
                    max(dragStartOffset + width, -trailingWidth),
                    leadingWidth
                )
            },
            onEnded: { location, velocity in
                guard horizontalLock, let start = panStart else {
                    panStart = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        suppressTap = false
                    }
                    return
                }
                horizontalLock = false
                isDragging = false
                let translation = location.x - start.x

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    suppressTap = false
                }
                // 全划：右滑方向 → 置顶；左滑方向（待办）→ 标记完成
                if velocity > 700 || translation > 150 {
                    haptic.impactOccurred()
                    actions.onTogglePin(record)
                    panStart = nil
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) { offset = 0 }
                    return
                }
                if record.isTodo, velocity < -700 || translation < -150 {
                    haptic.impactOccurred()
                    actions.onToggleDone(record)
                    panStart = nil
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) { offset = 0 }
                    return
                }
                settle()
                panStart = nil
            }
        )
    }

    /// 松手后的吸附：关闭干脆，展开轻微回弹
    private func settle() {
        let target: CGFloat
        if offset > openThreshold {
            target = leadingWidth
        } else if record.isTodo, offset < -openThreshold {
            target = -trailingWidth
        } else {
            target = 0
        }
        if target != 0, target != offset {
            haptic.impactOccurred()
        }
        let spring: Animation = target == 0
            ? .spring(response: 0.26, dampingFraction: 0.88)
            : .spring(response: 0.3, dampingFraction: 0.72)
        withAnimation(spring) { offset = target }
    }

    private func handleTap() {
        if abs(offset) > 2 {
            close()
        } else if !suppressTap {
            actions.onEdit(record)
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) { offset = 0 }
    }
}

/// 记录动作封装
struct RecordActions {
    let onToggleDone: (Record) -> Void
    let onEdit: (Record) -> Void
    let onDelete: (Record) -> Void
    /// 切换置顶
    var onTogglePin: (Record) -> Void = { _ in }
    /// 长按 → 设为输入栏引用
    var onQuote: (Record) -> Void = { _ in }
    /// 点击引用块：跳转滚动到被引用记录
    var onQuoteTap: (Record) -> Void = { _ in }
    /// 依据 ID 解析被引用记录
    var quoteProvider: (UUID) -> Record? = { _ in nil }
}

/// 全屏看图：下滑关闭
struct PhotoViewer: View {
    let photoData: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGSize = .zero

    private var dismissProgress: CGFloat {
        min(1, max(0, abs(dragOffset.height) / 300))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - Double(dismissProgress) * 0.7)
                .ignoresSafeArea()
            if let data = photoData, let image = RecordImageCache.image(for: data, key: "viewer") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(1 - dismissProgress * 0.15, anchor: dragOffset.height > 0 ? .bottom : .top)
                    .offset(dragOffset)
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .padding(20)
                }
                Spacer()
            }
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if abs(value.translation.width) < abs(value.translation.height) {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if abs(value.translation.height) > 120 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onTapGesture { dismiss() }
    }
}
