import Foundation
import AVFoundation

/// 语音录制与播放。
@Observable
final class AudioHelper: NSObject, AVAudioRecorderDelegate {
    static let shared = AudioHelper()

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?

    /// 正在录制的文件名与已录时长
    private(set) var isRecording = false
    private(set) var currentFileName: String?
    private(set) var elapsed: TimeInterval = 0

    private(set) var playingId: UUID?
    private(set) var isPlaying = false

    private(set) var lastRecordedFileName: String?
    private(set) var lastDuration: TimeInterval = 0

    private var baseURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func url(for fileName: String) -> URL {
        baseURL.appendingPathComponent(fileName)
    }

    // MARK: 录音

    func startRecording() {
        guard !isRecording else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        if session.recordPermission == .denied {
            return
        }
        session.requestRecordPermission { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async {
                if granted {
                    self.beginRecording()
                } else {
                    self.isRecording = false
                }
            }
        }
    }

    private func beginRecording() {
        let fileName = "\(UUID().uuidString).m4a"
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let rec = try AVAudioRecorder(url: url(for: fileName), settings: settings)
            rec.delegate = self
            rec.record()
            recorder = rec
            currentFileName = fileName
            elapsed = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.elapsed = rec.currentTime
            }
        } catch {
            isRecording = false
        }
    }

    /// 结束并返回（文件名, 时长）；取消返回 nil
    func stopRecording(cancel: Bool) -> (String, TimeInterval)? {
        timer?.invalidate()
        timer = nil
        defer {
            isRecording = false
            recorder = nil
            currentFileName = nil
            elapsed = 0
        }
        guard let rec = recorder, let name = currentFileName else { return nil }
        let duration = rec.currentTime
        rec.stop()
        if cancel || duration < 0.5 {
            try? FileManager.default.removeItem(at: url(for: name))
            return nil
        }
        lastRecordedFileName = name
        lastDuration = duration
        return (name, duration)
    }

    // MARK: 播放

    func togglePlay(fileName: String, recordId: UUID) {
        if isPlaying, playingId == recordId {
            player?.stop()
            isPlaying = false
            playingId = nil
            return
        }
        player?.stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        player = try? AVAudioPlayer(contentsOf: url(for: fileName))
        player?.delegate = self
        player?.play()
        isPlaying = true
        playingId = recordId
    }

    func deleteVoiceFile(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}

extension AudioHelper: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        playingId = nil
    }
}
