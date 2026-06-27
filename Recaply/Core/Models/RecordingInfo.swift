import Foundation

struct RecordingInfo: Identifiable, Equatable {
    let id: UUID
    var title: String?
    var tag: SessionTag
    let createdAt: Date
    var duration: TimeInterval
    var audioURL: URL?
    var videoURL: URL?
    var status: PipelineStatus
}
