import Combine
import Foundation

@MainActor
final class PipelineCoordinator: ObservableObject {
    enum Stage: Int, CaseIterable, Hashable {
        case transcribing, classifying, enhancing, summarizing

        var title: String {
            switch self {
            case .transcribing: return "Listening to your session"
            case .classifying: return "Finding key moments"
            case .enhancing: return "Polishing the notes"
            case .summarizing: return "Preparing your recap"
            }
        }

        var subtitle: String {
            switch self {
            case .transcribing: return "Converting the audio into readable text."
            case .classifying: return "Separating questions, actions, and decisions."
            case .enhancing: return "Cleaning filler words and formatting sections."
            case .summarizing: return "Creating a concise review you can present."
            }
        }
    }

    @Published var activeStage: Stage?
    @Published var completed: Set<Stage> = []
    @Published var failedStage: Stage?
    @Published var resultRecordingID: UUID?
    @Published var errorMessage: String?
    @Published var warningMessage: String?
    @Published var isRunning = false

    private let transcriber: TranscriptionProviding
    private let classifier: ClassificationService
    private let enhancer: TranscriptEnhancementService
    private let summarizer: SummarizationService
    private let repo: RecordingRepository
    private let notifications: RecapNotificationService
    private var runningRecordingID: UUID?

    init(transcriber: TranscriptionProviding = TranscriptionService.shared,
         classifier: ClassificationService = .shared,
         enhancer: TranscriptEnhancementService = .shared,
         summarizer: SummarizationService = .shared,
         repo: RecordingRepository = .shared,
         notifications: RecapNotificationService = .shared) {
        self.transcriber = transcriber
        self.classifier = classifier
        self.enhancer = enhancer
        self.summarizer = summarizer
        self.repo = repo
        self.notifications = notifications
    }

    func run(_ recording: RecordingInfo) async {
        guard runningRecordingID != recording.id else { return }
        runningRecordingID = recording.id
        isRunning = true
        completed.removeAll()
        failedStage = nil
        resultRecordingID = nil
        errorMessage = nil
        warningMessage = nil
        repo.save(recording: recording)

        var info = recording
        var warnings: [String] = []
        do {
            guard let audioURL = recording.audioURL else { throw PipelineError.missingAudio }

            activeStage = .transcribing
            info.status = .transcribing
            repo.update(info)
            let segments: [TranscriptSegmentModel]
            do {
                segments = try await transcriber.transcribe(audioAt: audioURL)
            } catch {
                let fallbackText = recording.liveTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let fallbackSegments = TranscriptSegmenter.segmentText(fallbackText)
                guard !fallbackSegments.isEmpty else { throw error }
                segments = fallbackSegments
                warnings.append("Transcription server issue: \(error.localizedDescription). Recaply used the live transcript fallback, so timestamps may be less precise.")
            }
            completed.insert(.transcribing)

            activeStage = .classifying
            info.status = .classifying
            repo.update(info)
            let labeled = classifier.classify(segments)
            repo.appendSegments(labeled, to: info)
            completed.insert(.classifying)

            activeStage = .enhancing
            info.status = .enhancing
            repo.update(info)
            let enhancedResult = try await enhancer.enhanceWithDiagnostics(segments: labeled, tag: recording.tag)
            if let warning = enhancedResult.warning { warnings.append(warning) }
            repo.saveEnhancement(enhancedResult.payload, to: info)
            completed.insert(.enhancing)

            activeStage = .summarizing
            info.status = .summarizing
            repo.update(info)
            let summaryResult = try await summarizer.summarizeWithDiagnostics(segments: labeled, tag: recording.tag)
            if let warning = summaryResult.warning { warnings.append(warning) }
            let summary = summaryResult.payload
            repo.saveSummary(summary, to: info)
            completed.insert(.summarizing)

            if shouldGenerateTitle(for: info.title) {
                info.title = Self.generateTitle(summary: summary, segments: labeled, tag: recording.tag)
            }
            info.status = .ready
            repo.update(info)
            activeStage = nil
            isRunning = false
            runningRecordingID = nil
            resultRecordingID = info.id
            warningMessage = Self.combinedWarning(from: warnings)
            await notifications.notifyReady(title: info.title ?? "\(info.tag.title) Recap")
        } catch {
            failedStage = activeStage
            errorMessage = error.localizedDescription
            info.status = .failed
            repo.update(info)
            isRunning = false
            runningRecordingID = nil
            await notifications.notifyFailed(title: info.title ?? "\(info.tag.title) Recap")
        }
    }

    private func shouldGenerateTitle(for title: String?) -> Bool {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    private static func generateTitle(summary: SummaryPayload, segments: [TranscriptSegmentModel], tag: SessionTag) -> String {
        let candidates = [
            summary.overview,
            summary.keyPoints.first,
            segments.first?.text
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        let source = candidates.first { !$0.isEmpty } ?? "\(tag.title) Recap"
        let cleaned = source
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "This \(tag.rawValue) covered ", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return titleCase(shortTitle(from: cleaned, fallback: "\(tag.title) Recap"))
    }

    private static func shortTitle(from text: String, fallback: String) -> String {
        guard !text.isEmpty else { return fallback }

        let words = text.split { $0.isWhitespace || $0.isNewline }
        if words.count > 1 {
            let title = words.prefix(8).joined(separator: " ")
            return title.count > 58 ? String(title.prefix(55)).trimmingCharacters(in: .whitespacesAndNewlines) + "…" : title
        }

        return text.count > 24 ? String(text.prefix(22)) + "…" : text
    }

    private static func titleCase(_ text: String) -> String {
        guard text.range(of: " ", options: .literal) != nil else { return text }
        return text
            .split(separator: " ")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func combinedWarning(from warnings: [String]) -> String? {
        let uniqueWarnings = Array(NSOrderedSet(array: warnings)) as? [String] ?? warnings
        guard !uniqueWarnings.isEmpty else { return nil }
        return uniqueWarnings.joined(separator: "\n")
    }
}

enum PipelineError: LocalizedError {
    case missingAudio

    var errorDescription: String? {
        "The recording does not have an audio file to process."
    }
}
