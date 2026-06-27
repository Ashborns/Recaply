import Foundation

enum SentenceLabel: String, Codable, CaseIterable {
    case actionItem = "action_item"
    case decision
    case question
    case discussion
}
