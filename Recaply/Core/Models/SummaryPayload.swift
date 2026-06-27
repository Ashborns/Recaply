import Foundation

struct SummaryPayload: Codable, Equatable {
    let overview: String
    let actionItems: [String]
    let decisions: [String]
    let keyPoints: [String]
}
