import SwiftUI
import PhotosUI

/// 底部输入栏：文字即时入流；可切待办模式、选照片（进编辑器）、按住录语音。
struct RecordInputBar: View {
    var onSend: (String, Bool) -> Void
    var onPickPhoto: (Data) -> Void
    var onVoiceDone: (String, TimeInterval) -> Void

    @Environment(AppSettings.self) private var settings
    @State private var draft = ""
    @State private var todoMode = false
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var focused: Bool

    @State private var recording = false
    @State private var elapsed: TimeInterval = 0
    @State private var pulse = false
    private var audio = AudioHelper.shared

    var body: some View {
        VStack(spacing: 0) {
            if recording {
                recordingBar
            } else {
                inputBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    todoMode.toggle()
                }
            } label: {
                Image(systemName: todoMode ? "checklist" : "checklist")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(todoMode ? Color.onPrimary : Color.secondaryText)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(todoMode ? Color.accent(for: settings.accent) : Color.chipFill))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .sensoryFeedback(.selection, trigger: todoMode)

            TextField(todoMode ? "添加待办…" : "记录此刻…", text: $draft, axis: .vertical)
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
                Image(systemName: "arrow.up")
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

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed, todoMode)
        draft = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 按住录音：按下开始，松开确认（<0.5s 自动取消）
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
                    .background(Circle().fill(Color.primaryText))
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
