import SwiftUI
import UIKit

/// 任务相关动作的统一封装，便于在各视图间传递。
struct TaskActions {
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onArchive: (TaskItem) -> Void
    let onRestore: (TaskItem) -> Void
}

/// 单条任务行：
/// - 右滑（leading）：标记完成 / 归档页中为恢复
/// - 左滑（trailing）：归档 + 删除（归档页中仅删除）
/// - 点复选框：切换完成
/// - 点行：直接进入编辑器
struct TaskRowView: View {
    enum RowContext {
        case active    // Home / Someday
        case archive   // Archive
    }

    let task: TaskItem
    var subtitle: String? = nil
    var context: RowContext = .active
    let actions: TaskActions

    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var suppressTap = false

    private let actionSize: CGFloat = 48
    private let trailingGap: CGFloat = 10
    private let openThreshold: CGFloat = 52
    private let fullSwipeDistance: CGFloat = 170
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var leadingWidth: CGFloat { actionSize }
    private var trailingWidth: CGFloat {
        context == .active ? actionSize * 2 + trailingGap : actionSize
    }

    private var leadingProgress: CGFloat {
        min(1, max(0, offset / leadingWidth))
    }

    private var trailingProgress: CGFloat {
        min(1, max(0, -offset / trailingWidth))
    }

    var body: some View {
        ZStack {
            actionsLayer
            rowContent
                .offset(x: offset)
                .simultaneousGesture(dragGesture)
        }
        .padding(.vertical, 5)
    }

    // MARK: 前景内容

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                actions.onToggle(task)
            } label: {
                checkbox
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(task.isCompleted ? Color.secondaryText : Color.primaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .animation(.easeInOut(duration: 0.25), value: task.isCompleted)
                if let subtitle {
                    HStack(spacing: 5) {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular))
                        if task.wantsReminder {
                            Image(systemName: "bell")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .foregroundStyle(Color.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if task.wantsReminder && subtitle == nil {
                Image(systemName: "bell")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondaryText.opacity(0.7))
        }
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
    }

    private var checkbox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(task.isCompleted ? Color.primaryText : Color.chipFill)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(task.isCompleted ? Color.clear : Color.checkboxBorder, lineWidth: 1.5)
            if task.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.onPrimary)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: 23, height: 23)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: task.isCompleted)
    }

    // MARK: 滑动操作层（跟随滑动进度渐显 + 弹性缩放）

    private var actionsLayer: some View {
        HStack(spacing: trailingGap) {
            Button {
                runLeading()
            } label: {
                actionIcon(
                    systemName: context == .active
                        ? (task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                        : "arrow.uturn.backward.square",
                    background: Color.primaryText,
                    foreground: Color.onPrimary
                )
            }
            .buttonStyle(.plain)
            .opacity(leadingProgress)
            .scaleEffect(0.7 + 0.3 * leadingProgress)

            Spacer(minLength: 0)

            if context == .active {
                Button {
                    close()
                    haptic.impactOccurred()
                    actions.onArchive(task)
                } label: {
                    actionIcon(
                        systemName: "archivebox",
                        background: Color.chipFill,
                        foreground: Color.primaryText
                    )
                }
                .buttonStyle(.plain)
                .opacity(trailingProgress)
                .scaleEffect(0.7 + 0.3 * trailingProgress)
            }

            Button {
                close()
                haptic.impactOccurred()
                actions.onDelete(task)
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
        .padding(.horizontal, 2)
        .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: offset)
    }

    private func actionIcon(systemName: String, background: Color, foreground: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: actionSize, height: actionSize)
            .background(Circle().fill(background))
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
                // 用速度预判结束位置，让快速轻扫也能触发
                let predicted = value.predictedEndTranslation.width
                if abs(translation) > 10 {
                    suppressTap = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        suppressTap = false
                    }
                }
                // 全划手势直接触发（实际位移或预测位移任一达标）
                if dragStartOffset == 0 {
                    let rightHit = translation > fullSwipeDistance || predicted > fullSwipeDistance * 1.6
                    let leftHit = translation < -fullSwipeDistance || predicted < -fullSwipeDistance * 1.6
                    if rightHit {
                        runLeading()
                        return
                    }
                    if leftHit {
                        if context == .archive {
                            haptic.impactOccurred()
                            actions.onDelete(task)
                        } else if translation < -(fullSwipeDistance + 110)
                                  || predicted < -(fullSwipeDistance * 1.6 + 110) {
                            haptic.impactOccurred()
                            actions.onArchive(task)
                        } else {
                            settle()
                        }
                        return
                    }
                }
                settle()
            }
    }

    /// 松手后的吸附：关闭要快而干脆，展开带一点弹跳
    private func settle() {
        let target: CGFloat
        if offset > openThreshold {
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
        withAnimation(spring) {
            offset = target
        }
    }

    private func handleTap() {
        if abs(offset) > 2 {
            close()
        } else if !suppressTap {
            actions.onEdit(task)
        }
    }

    private func runLeading() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) { offset = 0 }
        haptic.impactOccurred()
        if context == .active {
            actions.onToggle(task)
        } else {
            actions.onRestore(task)
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) { offset = 0 }
    }
}
