import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case authorizationDenied
    case recognizerUnavailable
    case requestFailed(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition permission is required to transcribe recordings."
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable for this locale."
        case .requestFailed(let message):
            return "Speech recognition failed: \(message)"
        case .emptyTranscript:
            return "No speech was detected in this recording."
        }
    }
}

protocol TranscriptionProviding {
    func transcribe(audioAt url: URL, locale: Locale) async throws -> [TranscriptSegmentModel]
}

extension TranscriptionProviding {
    func transcribe(audioAt url: URL) async throws -> [TranscriptSegmentModel] {
        try await transcribe(audioAt: url, locale: Locale(identifier: "en-US"))
    }
}

enum TranscriptSegmenter {
    static func segment(_ pieces: [(text: String, time: TimeInterval)]) -> [TranscriptSegmentModel] {
        var out: [TranscriptSegmentModel] = []
        var buffer = ""
        var bufferTime: TimeInterval = 0
        var index = 0
        let terminals: Set<Character> = [".", "!", "?", "。", "！", "？"]

        for piece in pieces {
            if buffer.isEmpty { bufferTime = piece.time }
            buffer += buffer.isEmpty ? piece.text : " " + piece.text

            if piece.text.last.map({ terminals.contains($0) }) == true {
                let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    out.append(TranscriptSegmentModel(index: index, text: text, timestamp: bufferTime))
                    index += 1
                }
                buffer = ""
            }
        }

        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            out.append(TranscriptSegmentModel(index: index, text: tail, timestamp: bufferTime))
        }
        return out
    }
}

final class TranscriptionService: TranscriptionProviding {
    static let shared = TranscriptionService()

    private init() {}

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(audioAt url: URL, locale: Locale = Locale(identifier: "en-US")) async throws -> [TranscriptSegmentModel] {
        guard await requestAuthorization() else { throw TranscriptionError.authorizationDenied }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // Lab note: iOS speech recognition has practical task-duration limits. The first
        // lab verification should test a long recording and, if needed, split audio into
        // overlapping windows before calling this same recognition path per window.
        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            func resumeOnce(_ result: Result<[TranscriptSegmentModel], Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    resumeOnce(.failure(TranscriptionError.requestFailed(error.localizedDescription)))
                    return
                }

                guard let result, result.isFinal else { return }

                let transcription = result.bestTranscription
                let pieces = transcription.segments.map { segment in
                    (text: segment.substring, time: segment.timestamp)
                }
                let segments = TranscriptSegmenter.segment(pieces)

                if !segments.isEmpty {
                    resumeOnce(.success(segments))
                    return
                }

                let fallbackText = transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fallbackText.isEmpty {
                    resumeOnce(.success([TranscriptSegmentModel(index: 0, text: fallbackText, timestamp: 0)]))
                } else {
                    resumeOnce(.failure(TranscriptionError.emptyTranscript))
                }
            }
        }
    }
}
