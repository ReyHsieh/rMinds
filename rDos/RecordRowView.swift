import SwiftUI

/// 时间线上的一条记录：左侧时间列 + 右侧内容。
/// 待办可勾选（右滑）、所有类型左滑删除、点按进入编辑。
struct RecordRowView: View {
    let record: Record
    var actions: RecordActions
    var frameKey: String? = nil

    @Environment(AppSettings.self) private var settings
    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var suppressTap = false
    @State private var showPhoto = false

    private var audio = AudioHelper.shared

    private let actionSize: CGFloat = 44
    private let openThreshold: CGFloat = 48
    private let fullSwipeDistance: CGFloat = 150
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var leadingWidth: CGFloat { record.isTodo ? actionSize : 0 }
    private var trailingWidth: CGFloat { actionSize }

    var body: some View {
        ZStack {
            actionsLayer
            content
                .offset(x: offset)
                .simultaneousGesture(dragGesture)
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
                if record.isPinned {
                    Label("已置顶", systemImage: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                }
                switch record.kind {
                case .text: textBody
                case .todo: todoBody
                case .photo: photoBody
                case .voice: voiceBody
                }
            }
            .padding(.leading, record.isHighlighted ? 8 : 0)
            .overlay(alignment: .leading) {
                if record.isHighlighted {
                    Capsule()
                        .fill(Color.accent(for: settings.accent))
                        .frame(width: 3)
                }
            }
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
            Button {
                actions.onToggleDone(record)
            } label: {
                checkbox
            }
            .buttonStyle(.plain)

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
        VStack(alignment: .leading, spacing: 6) {
            if let data = record.photoData, let image = UIImage(data: data) {
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
            if !record.text.isEmpty {
                Text(record.text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var voiceBody: some View {
        Button {
            guard let file = record.voiceFileName else { return }
            audio.togglePlay(fileName: file, recordId: record.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: audio.isPlaying && audio.playingId == record.id ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.primaryText)
                HStack(spacing: 2) {
                    ForEach(0..<14, id: \.self) { i in
                        Capsule()
                            .fill(Color.primaryText.opacity(0.55))
                            .frame(width: 2.5, height: CGFloat([9, 15, 7, 18, 12, 20, 8, 14, 10, 17, 6, 13, 9, 16][i]))
                    }
                }
                Text(String(format: "%d:%02d", Int(record.voiceDuration) / 60, Int(record.voiceDuration) % 60))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.cardTint))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
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
        let index = DayPlanner.dayIndex(of: day, hour: 4, minute: 0)
        var label = DayPlanner.dayLabel(for: index, day: day)
            .replacingOccurrences(of: " · ", with: " ")
            .capitalized
        if let time = record.dueTime {
            label += " · \(DayPlanner.hm(time))"
        }
        return label
    }

    // MARK: 滑动操作层

    private var actionsLayer: some View {
        HStack(spacing: 0) {
            if record.isTodo {
                Button {
                    runLeading()
                } label: {
                    actionIcon(
                        systemName: record.isDone ? "arrow.uturn.backward" : "checkmark",
                        background: Color.primaryText,
                        foreground: Color.onPrimary
                    )
                }
                .buttonStyle(.plain)
                .opacity(leadingProgress)
                .scaleEffect(0.7 + 0.3 * leadingProgress)
            }
            Spacer(minLength: 0)
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
            .opacity(trailingProgress)
            .scaleEffect(0.7 + 0.3 * trailingProgress)
        }
        .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: offset)
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
        min(1, max(0, -offset / trailingWidth))
    }

    // MARK: 手势

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartOffset = offset
                }
                offset = min(
                    max(dragStartOffset + value.translation.width, -trailingWidth),
                    leadingWidth
                )
            }
            .onEnded { value in
                isDragging = false
                let translation = value.translation.width
                let predicted = value.predictedEndTranslation.width
                if abs(translation) > 10 {
                    suppressTap = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        suppressTap = false
                    }
                }
                if dragStartOffset == 0 {
                    if record.isTodo,
                       translation > fullSwipeDistance || predicted > fullSwipeDistance * 1.6 {
                        runLeading()
                        return
                    }
                    if translation < -fullSwipeDistance || predicted < -fullSwipeDistance * 1.6 {
                        haptic.impactOccurred()
                        actions.onDelete(record)
                        return
                    }
                }
                settle()
            }
    }

    private func settle() {
        let target: CGFloat
        if record.isTodo, offset > openThreshold {
            target = leadingWidth
        } else if offset < -openThreshold {
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

    private func runLeading() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) { offset = 0 }
        haptic.impactOccurred()
        actions.onToggleDone(record)
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
}

/// 全屏看图
struct PhotoViewer: View {
    let photoData: Data?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let data = photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
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
        .onTapGesture { dismiss() }
    }
}
