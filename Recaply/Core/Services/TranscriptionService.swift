import AVFoundation
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

enum RecaplySpeechLanguage: String, CaseIterable, Identifiable {
    case automatic
    case indonesian
    case english
    case mandarinSimplified
    case mandarinTraditional
    case japanese
    case korean

    static let defaultsKey = "recaply_speech_language"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Auto"
        case .indonesian: return "Indonesian"
        case .english: return "English"
        case .mandarinSimplified: return "Mandarin (Simplified)"
        case .mandarinTraditional: return "Mandarin (Traditional)"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        }
    }

    var caption: String {
        switch self {
        case .automatic: return "Tries device language, Indonesian, English, Mandarin, Japanese, and Korean."
        case .indonesian: return "Best for Bahasa Indonesia recordings."
        case .english: return "Best for English recordings."
        case .mandarinSimplified: return "Best for Putonghua / simplified Chinese notes."
        case .mandarinTraditional: return "Best for Mandarin with traditional Chinese output."
        case .japanese: return "Best for Japanese recordings."
        case .korean: return "Best for Korean recordings."
        }
    }

    var primaryLocale: Locale {
        Locale(identifier: localeIdentifiers[0])
    }

    var localeIdentifiers: [String] {
        switch self {
        case .automatic:
            return Self.deduplicated(Locale.preferredLanguages + Self.fallbackLocaleIdentifiers)
        case .indonesian:
            return ["id-ID"]
        case .english:
            return ["en-US"]
        case .mandarinSimplified:
            return ["zh-Hans", "zh-CN"]
        case .mandarinTraditional:
            return ["zh-Hant", "zh-TW"]
        case .japanese:
            return ["ja-JP"]
        case .korean:
            return ["ko-KR"]
        }
    }

    var recognitionLocales: [Locale] {
        Self.deduplicated(localeIdentifiers + Self.fallbackLocaleIdentifiers).map(Locale.init(identifier:))
    }

    static var selected: RecaplySpeechLanguage {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
        return raw.flatMap(RecaplySpeechLanguage.init(rawValue:)) ?? .automatic
    }

    private static let fallbackLocaleIdentifiers = ["id-ID", "en-US", "zh-Hans", "zh-CN", "ja-JP", "ko-KR"]

    private static func deduplicated(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers.compactMap { identifier in
            let normalized = identifier.replacingOccurrences(of: "_", with: "-")
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }
}

enum SpeechRecognitionPreferences {
    static let preferOnDeviceKey = "recaply_on_device_speech"

    static var prefersOnDevice: Bool {
        UserDefaults.standard.bool(forKey: preferOnDeviceKey)
    }
}

protocol TranscriptionProviding {
    func transcribe(audioAt url: URL, locale: Locale) async throws -> [TranscriptSegmentModel]
}

extension TranscriptionProviding {
    func transcribe(audioAt url: URL) async throws -> [TranscriptSegmentModel] {
        try await transcribe(audioAt: url, locale: RecaplySpeechLanguage.selected.primaryLocale)
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

    static func segmentText(_ text: String) -> [TranscriptSegmentModel] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let separators = CharacterSet(charactersIn: ".!?。！？\n")
        let parts = trimmed
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let chunks = parts.isEmpty ? [trimmed] : parts
        return chunks.enumerated().map { index, text in
            TranscriptSegmentModel(index: index, text: text, timestamp: TimeInterval(index) * 6)
        }
    }
}

final class TranscriptionService: TranscriptionProviding {
    static let shared = TranscriptionService()
    private let chunkDuration: TimeInterval = 50

    private init() {}

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(audioAt url: URL, locale: Locale = Locale(identifier: "id-ID")) async throws -> [TranscriptSegmentModel] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? NSNumber
        guard fileSize?.intValue ?? 0 > 2_048 else {
            throw TranscriptionError.emptyTranscript
        }

        guard await requestAuthorization() else { throw TranscriptionError.authorizationDenied }

        let duration = await audioDuration(for: url)
        if duration > chunkDuration {
            return try await transcribeChunked(audioAt: url, duration: duration, locale: locale)
        }

        return try await transcribeWithPreferredLocales(audioAt: url, locale: locale)
    }

    private func transcribeWithPreferredLocales(audioAt url: URL, locale: Locale) async throws -> [TranscriptSegmentModel] {
        let preferredLocales = preferredLocales(startingWith: locale)
        var lastError: Error = TranscriptionError.emptyTranscript
        for candidate in preferredLocales {
            do {
                let segments = try await transcribeOnce(audioAt: url, locale: candidate)
                if !segments.isEmpty { return segments }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func transcribeChunked(audioAt url: URL, duration: TimeInterval, locale: Locale) async throws -> [TranscriptSegmentModel] {
        var allSegments: [TranscriptSegmentModel] = []
        var lastError: Error = TranscriptionError.emptyTranscript
        var start: TimeInterval = 0

        while start < duration {
            let length = min(chunkDuration, duration - start)
            let chunkURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("recaply-speech-\(UUID().uuidString).m4a")

            do {
                try await exportChunk(from: url, to: chunkURL, start: start, duration: length)
                let chunkSegments = try await transcribeWithPreferredLocales(audioAt: chunkURL, locale: locale)
                allSegments.append(contentsOf: chunkSegments.map { segment in
                    TranscriptSegmentModel(
                        id: segment.id,
                        index: segment.index,
                        text: segment.text,
                        timestamp: segment.timestamp + start,
                        label: segment.label,
                        confidence: segment.confidence
                    )
                })
            } catch {
                lastError = error
            }

            try? FileManager.default.removeItem(at: chunkURL)
            start += chunkDuration
        }

        guard !allSegments.isEmpty else { throw lastError }
        return allSegments.enumerated().map { index, segment in
            TranscriptSegmentModel(
                id: segment.id,
                index: index,
                text: segment.text,
                timestamp: segment.timestamp,
                label: segment.label,
                confidence: segment.confidence
            )
        }
    }

    private func audioDuration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let time = (try? await asset.load(.duration)) ?? .zero
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? max(0, seconds) : 0
    }

    private func exportChunk(from sourceURL: URL, to outputURL: URL, start: TimeInterval, duration: TimeInterval) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.requestFailed("Could not prepare audio chunk for recognition.")
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )

        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    let message = exporter.error?.localizedDescription ?? "Audio chunk export failed."
                    continuation.resume(throwing: TranscriptionError.requestFailed(message))
                default:
                    continuation.resume(throwing: TranscriptionError.requestFailed("Audio chunk export did not complete."))
                }
            }
        }
    }

    private func preferredLocales(startingWith locale: Locale) -> [Locale] {
        let selectedLanguage = RecaplySpeechLanguage.selected
        let selected = selectedLanguage.recognitionLocales
        var identifiers = [locale.identifier]
        identifiers.append(contentsOf: selected.map(\.identifier))
        if selectedLanguage == .automatic {
            identifiers.append(contentsOf: ["id-ID", "en-US", "zh-Hans", "zh-CN", "ja-JP", "ko-KR"])
        }

        var seen = Set<String>()
        return identifiers.compactMap { identifier in
            let normalized = identifier.replacingOccurrences(of: "_", with: "-")
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return Locale(identifier: normalized)
        }
    }

    private func transcribeOnce(audioAt url: URL, locale: Locale) async throws -> [TranscriptSegmentModel] {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = SpeechRecognitionPreferences.prefersOnDevice

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
