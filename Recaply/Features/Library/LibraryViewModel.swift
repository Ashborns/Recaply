import Foundation
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var recordings: [RecordingInfo] = []

    private let repo: RecordingRepository

    init(repo: RecordingRepository = .shared) {
        self.repo = repo
        reload()
    }

    var latest: RecordingInfo? { recordings.first }
    var older: [RecordingInfo] { Array(recordings.dropFirst()) }

    func reload() {
        recordings = repo.fetchRecordings()
    }
}
