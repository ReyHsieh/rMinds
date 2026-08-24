import Foundation
import Speech

/// 语音转文字：Apple Speech 框架，优先设备端识别（免费开发者账号可用）。
enum SpeechTranscriber {
    static func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return status == .authorized
    }

    /// 转写音频文件，返回文本
    static func transcribe(fileURL: URL, localeIdentifier: String = "zh-CN") async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw TranscribeError.unsupportedLocale
        }
        guard recognizer.isAvailable else {
            throw TranscribeError.unavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        if recognizer.supportsOnDeviceRecognition {
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    finished = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    enum TranscribeError: LocalizedError {
        case unsupportedLocale
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale: return "当前语言不支持识别"
            case .unavailable: return "语音识别暂不可用"
            }
        }
    }
}
