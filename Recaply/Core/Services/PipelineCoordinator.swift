import Combine
import Foundation

@MainActor
final class PipelineCoordinator: ObservableObject {
    enum Stage: Int, CaseIterable, Hashable {
        case transcribing, classifying, enhancing, summarizing

        var title: String {
            switch self {
            case .transcribing: return "Transcribing"
            case .classifying: return "Classifying"
            case .enhancing: return "Enhancing"
            case .summarizing: return "Summarizing"
            }
        }
    }

    @Published var activeStage: Stage?
    @Published var completed: Set<Stage> = []
    @Published var failedStage: Stage?
    @Published var resultRecordingID: UUID?
    @Published var errorMessage: String?

    private let transcriber: TranscriptionProviding
    private let classifier: ClassificationService
    private let enhancer: TranscriptEnhancementService
    private let summarizer: SummarizationService
    private let repo: RecordingRepository

    init(transcriber: TranscriptionProviding = TranscriptionService.shared,
         classifier: ClassificationService = .shared,
         enhancer: TranscriptEnhancementService = .shared,
         summarizer: SummarizationService = .shared,
         repo: RecordingRepository = .shared) {
        self.transcriber = transcriber
        self.classifier = classifier
        self.enhancer = enhancer
        self.summarizer = summarizer
        self.repo = repo
    }

    func run(_ recording: RecordingInfo) async {
        completed.removeAll()
        failedStage = nil
        resultRecordingID = nil
        errorMessage = nil
        repo.save(recording: recording)

        var info = recording
        do {
            guard let audioURL = recording.audioURL else { throw PipelineError.missingAudio }

            activeStage = .transcribing
            info.status = .transcribing
            repo.update(info)
            let segments = try await transcriber.transcribe(audioAt: audioURL)
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
            let enhanced = await enhancer.enhance(segments: labeled, tag: recording.tag)
            repo.saveEnhancement(enhanced, to: info)
            completed.insert(.enhancing)

            activeStage = .summarizing
            info.status = .summarizing
            repo.update(info)
            if let summary = try? await summarizer.summarize(segments: labeled, tag: recording.tag) {
                repo.saveSummary(summary, to: info)
            }
            completed.insert(.summarizing)

            info.status = .ready
            repo.update(info)
            activeStage = nil
            resultRecordingID = info.id
        } catch {
            failedStage = activeStage
            errorMessage = error.localizedDescription
            info.status = .failed
            repo.update(info)
        }
    }
}

enum PipelineError: LocalizedError {
    case missingAudio

    var errorDescription: String? {
        "The recording does not have an audio file to process."
    }
}
