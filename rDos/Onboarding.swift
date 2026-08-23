import SwiftUI

// MARK: - 引导状态机

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case createTask
    case completeTask
    case done
}

@Observable
final class OnboardingManager {
    static let shared = OnboardingManager()
    private static let hasSeenKey = "hasSeenOnboarding"

    private(set) var step: OnboardingStep?
    var isActive: Bool { step != nil }

    /// 首次启动自动播放（正式版与调试版一致；设置里可重新触发）。
    func startIfNeeded() {
        guard step == nil, !UserDefaults.standard.bool(forKey: Self.hasSeenKey) else { return }
        step = .welcome
    }

    func restart() {
        step = .welcome
    }

    func advance() {
        guard let current = step else { return }
        if current == .done {
            finish()
        } else {
            step = OnboardingStep(rawValue: current.rawValue + 1)
        }
    }

    func finish() {
        step = nil
        UserDefaults.standard.set(true, forKey: Self.hasSeenKey)
    }

    /// 任务被勾选完成时由行组件回调。
    func taskToggled(completed: Bool) {
        guard step == .completeTask, completed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if self.step == .completeTask { self.advance() }
        }
    }

    /// 编辑器关闭时回调：只有在引导期内真的创建了任务才前进。
    func editorDismissed(createdTask: Bool) {
        guard step == .createTask, createdTask else { return }
        advance()
    }
}

// MARK: - 引导浮层

struct OnboardingOverlay: View {
    let frames: [String: CGRect]
    @Environment(OnboardingManager.self) private var onboarding

    var body: some View {
        ZStack {
            switch onboarding.step {
            case .welcome:
                welcomeCard
            case .createTask:
                holeStep(
                    frameKey: "newTask",
                    text: "点击 “New task”\n创建你的第一个任务",
                    cardBelowHole: false
                )
            case .completeTask:
                holeStep(
                    frameKey: "firstTask",
                    text: "点击左侧方框\n把这个任务标记为完成",
                    cardBelowHole: true
                )
            case .done:
                doneCard
            case nil:
                EmptyView()
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: onboarding.step)
        .onAppear { skipIfTargetMissing() }
        .onChange(of: frames) { _ in skipIfTargetMissing() }
    }

    private func skipIfTargetMissing() {
        if onboarding.step == .completeTask, frames["firstTask"] == nil {
            onboarding.advance()
        }
    }

    // MARK: 卡片

    private var welcomeCard: some View {
        ZStack {
            DimBlock().ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.square")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.primaryText)
                Text("欢迎使用 rDos")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.primaryText)
                Text("极简待办清单。\n三步上手：创建任务、勾选完成、回顾归档。")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.secondaryText)
                    .multilineTextAlignment(.center)
                Button {
                    onboarding.advance()
                } label: {
                    Text("开始")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.onPrimary)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 12)
                        .background(Capsule(style: .continuous).fill(Color.primaryText))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
            }
            .padding(28)
            .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 40)
        }
    }

    private var doneCard: some View {
        ZStack {
            DimBlock().ignoresSafeArea()
            VStack(spacing: 18) {
                Text("一切就绪")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.primaryText)
                Text("开始记录你的待办吧。\n完成的任务会在次日归档。")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.secondaryText)
                    .multilineTextAlignment(.center)
                Button {
                    onboarding.finish()
                } label: {
                    Text("完成")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.onPrimary)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 12)
                        .background(Capsule(style: .continuous).fill(Color.primaryText))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 40)
        }
    }

    private func holeStep(frameKey: String, text: String, cardBelowHole: Bool) -> some View {
        ZStack {
            DimWithHole(hole: frames[frameKey] ?? .zero)
            if let rect = frames[frameKey] {
                GeometryReader { proxy in
                    let padded = rect.insetBy(dx: -10, dy: -10)
                    VStack(spacing: 0) {
                        if !cardBelowHole {
                            hintCard(text)
                                .padding(.bottom, 16)
                                .frame(
                                    maxHeight: max(0, padded.minY),
                                    alignment: .bottom
                                )
                        }
                        Spacer(minLength: 0)
                        if cardBelowHole {
                            hintCard(text)
                                .padding(.top, 16)
                                .frame(
                                    maxHeight: max(0, proxy.size.height - padded.maxY),
                                    alignment: .top
                                )
                        }
                    }
                }
            }
        }
    }

    private func hintCard(_ text: String) -> some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primaryText)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
    }
}

/// 挖孔遮罩：孔洞区域穿透点击，周围吸附点击并压暗。
struct DimWithHole: View {
    let hole: CGRect

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let padded = hole.insetBy(dx: -10, dy: -10)
            let clamped = CGRect(
                x: max(0, padded.minX),
                y: max(0, padded.minY),
                width: max(0, min(size.width, padded.maxX) - max(0, padded.minX)),
                height: max(0, min(size.height, padded.maxY) - max(0, padded.minY))
            )
            VStack(spacing: 0) {
                DimBlock()
                    .frame(height: max(0, clamped.minY))
                HStack(spacing: 0) {
                    DimBlock()
                        .frame(width: max(0, clamped.minX))
                    Color.clear
                        .frame(width: max(0, clamped.width), height: max(0, clamped.height))
                    DimBlock()
                        .frame(width: max(0, size.width - clamped.maxX))
                }
                .frame(height: max(0, clamped.height))
                DimBlock()
                    .frame(height: max(0, size.height - clamped.maxY))
            }
        }
        .ignoresSafeArea()
    }
}

/// 压暗色块，同时消费点击避免误触底层内容。
private struct DimBlock: View {
    var body: some View {
        Color.black.opacity(0.55)
            .contentShape(Rectangle())
            .onTapGesture {}
    }
}
