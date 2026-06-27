import Foundation
import Combine

@MainActor
final class RecordingDetailViewModel: ObservableObject {
    enum TranscriptMode: String, CaseIterable, Identifiable {
        case clean = "Clean"
        case polished = "Polished"
        case raw = "Raw"
        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .clean: return "wand.and.stars"
            case .polished: return "doc.richtext"
            case .raw: return "waveform"
            }
        }
    }

    @Published var detail: RecordingDetailData?
    @Published var mode: TranscriptMode = .clean
    @Published var checkedActionItems: Set<Int> = []
    @Published var exportTextURL: URL?
    @Published var exportJSONURL: URL?
    @Published var askQuestionText: String = ""
    @Published var askAnswerText: String?
    @Published var askWarningText: String?
    @Published var askErrorText: String?
    @Published var isAskingAI = false

    private let recordingID: UUID
    private let repo: RecordingRepository
    private let questionService: RecordingQuestionService
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()

    init(recordingID: UUID,
         repo: RecordingRepository = .shared,
         questionService: RecordingQuestionService = .shared,
         defaults: UserDefaults = .standard) {
        self.recordingID = recordingID
        self.repo = repo
        self.questionService = questionService
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

    var labelCounts: [SentenceLabel: Int] {
        Dictionary(grouping: segments, by: \.label).mapValues { $0.count }
    }

    var averageConfidence: Double {
        let values = segments.map(\.confidence).filter { $0 > 0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var actionItems: [String] {
        nonEmpty(summary?.actionItems)
            ?? segments.filter { $0.label == .actionItem }.map(\.text)
    }

    var decisions: [String] {
        nonEmpty(summary?.decisions)
            ?? segments.filter { $0.label == .decision }.map(\.text)
    }

    var keyPoints: [String] {
        nonEmpty(summary?.keyPoints)
            ?? Array(segments.filter { $0.label == .discussion }.prefix(4).map(\.text))
    }

    var overviewText: String {
        nonBlank(summary?.overview)
            ?? "Transcript is ready. Recaply classified \(segments.count) transcript segments on-device; add an API key to generate a richer LLM summary."
    }

    func reload() {
        detail = repo.fetchDetail(id: recordingID)
        refreshExportFiles()
    }

    func rename(to title: String) {
        repo.updateTitle(title, for: recordingID)
        reload()
    }

    func deleteRecording() {
        repo.deleteRecording(id: recordingID)
    }

    func toggleActionItem(at index: Int) {
        if checkedActionItems.contains(index) {
            checkedActionItems.remove(index)
        } else {
            checkedActionItems.insert(index)
        }
        defaults.set(Array(checkedActionItems), forKey: defaultsKey)
    }

    func askAI() async {
        let question = askQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAskingAI else { return }

        isAskingAI = true
        askAnswerText = nil
        askWarningText = nil
        askErrorText = nil

        let context = recordingContext()
        guard !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            askErrorText = "This recording does not have enough transcript or summary context yet."
            isAskingAI = false
            return
        }

        do {
            let result = try await questionService.answer(question: question, context: context)
            askAnswerText = result.payload
            askWarningText = result.warning
        } catch {
            askErrorText = error.localizedDescription
        }
        isAskingAI = false
    }

    func useSuggestedQuestion(_ question: String) {
        askQuestionText = question
    }

    private var defaultsKey: String { "recaply_checked_\(recordingID.uuidString)" }

    private func refreshExportFiles() {
        guard let detail else {
            exportTextURL = nil
            exportJSONURL = nil
            return
        }
        let safeTitle = filenameBase(for: detail.recording)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RecaplyExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let textURL = directory.appendingPathComponent("\(safeTitle).txt")
        let jsonURL = directory.appendingPathComponent("\(safeTitle).json")
        try? exportText(for: detail).write(to: textURL, atomically: true, encoding: .utf8)
        if let data = try? encoder.encode(ExportPayload(detail: detail)) {
            try? data.write(to: jsonURL, options: .atomic)
        }
        exportTextURL = textURL
        exportJSONURL = jsonURL
    }

    private func recordingContext() -> String {
        var lines: [String] = []
        if let recording {
            lines.append("Title: \(recording.title ?? "Untitled session")")
            lines.append("Type: \(recording.tag.title)")
            lines.append("Duration: \(recording.duration.asClock)")
        }
        lines.append("")
        lines.append("Overview:")
        lines.append(overviewText)
        appendSection("Action Items", actionItems, to: &lines)
        appendSection("Decisions", decisions, to: &lines)
        appendSection("Key Points", keyPoints, to: &lines)

        if !polishedSections.isEmpty {
            lines.append("Polished Notes")
            for section in polishedSections.prefix(8) {
                lines.append("- \(section.heading): \(section.body)")
            }
            lines.append("")
        }

        lines.append("Transcript")
        let transcriptLines = cleanSegments.prefix(160).map { clean -> String in
            let timestamp = self.segments.first(where: { $0.index == clean.index })?.timestamp ?? 0
            return "[\(timestamp.asClock)] \(clean.text)"
        }
        lines.append(contentsOf: transcriptLines)
        return lines.joined(separator: "\n")
    }

    private func exportText(for detail: RecordingDetailData) -> String {
        let recording = detail.recording
        var lines: [String] = []
        lines.append(recording.title ?? "Untitled session")
        lines.append("\(recording.tag.title) · \(recording.createdAt.mediumFormatted) · \(recording.duration.asClock)")
        lines.append("")
        lines.append("Overview")
        lines.append(overviewText)
        lines.append("")
        appendSection("Action Items", actionItems, to: &lines)
        appendSection("Decisions", decisions, to: &lines)
        appendSection("Key Points", keyPoints, to: &lines)
        lines.append("Transcript")
        for segment in cleanSegments {
            let timestamp = self.segments.first(where: { $0.index == segment.index })?.timestamp ?? 0
            lines.append("[\(timestamp.asClock)] \(segment.text)")
        }
        return lines.joined(separator: "\n")
    }

    private func appendSection(_ title: String, _ items: [String], to lines: inout [String]) {
        lines.append(title)
        if items.isEmpty {
            lines.append("- None")
        } else {
            lines.append(contentsOf: items.map { "- \($0)" })
        }
        lines.append("")
    }

    private func filenameBase(for recording: RecordingInfo) -> String {
        let title = recording.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = title?.isEmpty == false ? title! : "\(recording.tag.title)-\(recording.createdAt.mediumFormatted)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        return base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.reduce("") { $0 + String($1) }
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

private struct ExportPayload: Encodable {
    struct Recording: Encodable {
        let id: UUID
        let title: String?
        let mode: String
        let createdAt: Date
        let duration: TimeInterval
        let status: String
    }

    struct Segment: Encodable {
        let index: Int
        let timestamp: TimeInterval
        let text: String
        let label: String
        let confidence: Double
    }

    let recording: Recording
    let summary: SummaryPayload?
    let cleanTranscript: [EnhancedTranscriptPayload.CleanSegment]
    let polishedNotes: [EnhancedTranscriptPayload.TopicSection]
    let rawSegments: [Segment]

    init(detail: RecordingDetailData) {
        recording = Recording(
            id: detail.recording.id,
            title: detail.recording.title,
            mode: detail.recording.tag.rawValue,
            createdAt: detail.recording.createdAt,
            duration: detail.recording.duration,
            status: detail.recording.status.rawValue
        )
        summary = detail.summary
        cleanTranscript = detail.enhanced?.clean ?? detail.segments.map { .init(index: $0.index, text: $0.text) }
        polishedNotes = detail.enhanced?.polished ?? []
        rawSegments = detail.segments.map {
            Segment(index: $0.index, timestamp: $0.timestamp, text: $0.text, label: $0.label.rawValue, confidence: $0.confidence)
        }
    }
}
