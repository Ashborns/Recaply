import Foundation
import Combine

struct LibraryRecordingCard: Identifiable, Equatable {
    let recording: RecordingInfo
    let preview: String
    let actionItems: [String]
    let counts: [SentenceLabel: Int]

    var id: UUID { recording.id }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var cards: [LibraryRecordingCard] = []

    private let repo: RecordingRepository

    init(repo: RecordingRepository = .shared) {
        self.repo = repo
        reload()
    }

    var latest: LibraryRecordingCard? { cards.first }
    var older: [LibraryRecordingCard] { Array(cards.dropFirst()) }

    func reload() {
        cards = repo.fetchRecordings().map { recording in
            let detail = repo.fetchDetail(id: recording.id)
            let segments = detail?.segments ?? []
            let summary = detail?.summary
            let counts = Dictionary(grouping: segments, by: \.label).mapValues { $0.count }
            let preview = nonBlank(summary?.overview)
                ?? segments.first?.text
                ?? statusText(recording.status)
            let classifiedActionItems = segments.filter { $0.label == .actionItem }.prefix(3).map(\.text)
            let actionItems = nonEmpty(summary?.actionItems) ?? Array(classifiedActionItems)
            return LibraryRecordingCard(recording: recording, preview: preview, actionItems: actionItems, counts: counts)
        }
    }

    func delete(_ card: LibraryRecordingCard) {
        repo.deleteRecording(id: card.id)
        reload()
    }

    private func statusText(_ status: PipelineStatus) -> String {
        switch status {
        case .ready: return "AI notes are ready."
        case .failed: return "Processing failed. Transcript data may still be available."
        default: return "Processing status: \(status.rawValue.capitalized)."
        }
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func nonEmpty(_ value: [String]?) -> [String]? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
