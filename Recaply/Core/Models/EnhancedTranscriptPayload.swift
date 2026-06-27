import Foundation

// Persistence policy:
//   `clean` is NOT stored on the EnhancedTranscript entity. At write time each clean
//   text is written to the matching TranscriptSegment.cleanedText (matched by index).
//   At read time, reconstruct `clean` from each TranscriptSegment as (cleanedText ?? text).
//   `polished` is stored verbatim as EnhancedTranscript.polishedJSON.
struct EnhancedTranscriptPayload: Codable, Equatable {
    struct CleanSegment: Codable, Equatable { let index: Int; let text: String }
    struct TopicSection: Codable, Equatable { let heading: String; let body: String }
    let clean: [CleanSegment]
    let polished: [TopicSection]
}
