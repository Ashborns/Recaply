import Foundation
import Combine

@MainActor
final class RecordingDetailViewModel: ObservableObject {
    enum TranscriptMode: String, CaseIterable, Identifiable {
        case clean = "Clean"
        case polished = "Polished"
        case raw = "Raw"
        var id: String { rawValue }
    }

    @Published var detail: RecordingDetailData?
    @Published var mode: TranscriptMode = .clean
    @Published var checkedActionItems: Set<Int> = []

    private let recordingID: UUID
    private let repo: RecordingRepository
    private let defaults: UserDefaults

    init(recordingID: UUID, repo: RecordingRepository = .shared, defaults: UserDefaults = .standard) {
        self.recordingID = recordingID
        self.repo = repo
        self.defaults = defaults
        checkedActionItems = Set(defaults.array(forKey: defaultsKey) as? [Int] ?? [])
        reload()
    }

    var recording: RecordingInfo? { detail?.recording }
    var segments: [TranscriptSegmentModel] { detail?.segments ?? [] }
    var summary: SummaryPayload? { detail?.summary }
    var enhanced: EnhancedTranscriptPayload? { detail?.enhanced }

    var cleanSegments: [EnhancedTranscriptPayload.CleanSegment] {
        if let clean = enhanced?.clean, !clean.isEmpty { return clean }
        return segments.map { .init(index: $0.index, text: $0.text) }
    }

    var polishedSections: [EnhancedTranscriptPayload.TopicSection] {
        enhanced?.polished ?? []
    }

    var actionItems: [String] { summary?.actionItems ?? [] }

    func reload() {
        detail = repo.fetchDetail(id: recordingID)
    }

    func toggleActionItem(at index: Int) {
        if checkedActionItems.contains(index) {
            checkedActionItems.remove(index)
        } else {
            checkedActionItems.insert(index)
        }
        defaults.set(Array(checkedActionItems), forKey: defaultsKey)
    }

    private var defaultsKey: String { "recaply_checked_\(recordingID.uuidString)" }
}
