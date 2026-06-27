import Foundation

struct TranscriptSegmentModel: Identifiable, Equatable, Codable {
    let id: UUID
    let index: Int
    let text: String
    let timestamp: TimeInterval
    var label: SentenceLabel
    var confidence: Double

    init(id: UUID = UUID(), index: Int, text: String, timestamp: TimeInterval,
         label: SentenceLabel = .discussion, confidence: Double = 0) {
        self.id = id; self.index = index; self.text = text
        self.timestamp = timestamp; self.label = label; self.confidence = confidence
    }
}
