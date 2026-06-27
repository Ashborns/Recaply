import Foundation

struct EnhancedTranscriptPayload: Codable, Equatable {
    struct CleanSegment: Codable, Equatable { let index: Int; let text: String }
    struct TopicSection: Codable, Equatable { let heading: String; let body: String }
    let clean: [CleanSegment]
    let polished: [TopicSection]
}
