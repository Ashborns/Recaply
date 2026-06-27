import Foundation

final class ClassificationService {
    static let shared = ClassificationService(provider: StubClassifierProvider())

    private let provider: ClassificationProviding

    init(provider: ClassificationProviding) {
        self.provider = provider
    }

    func classify(_ text: String) -> (SentenceLabel, Double) {
        if let result = provider.predict(text) { return result }
        return (.discussion, 0)
    }

    func classify(_ segments: [TranscriptSegmentModel]) -> [TranscriptSegmentModel] {
        segments.map { segment in
            var updated = segment
            let (label, confidence) = classify(segment.text)
            updated.label = label
            updated.confidence = confidence
            return updated
        }
    }
}
