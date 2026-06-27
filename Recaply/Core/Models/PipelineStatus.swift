import Foundation

enum PipelineStatus: String, Codable {
    case captured, transcribing, classifying, enhancing, summarizing, ready, failed
}
