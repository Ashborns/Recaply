import CoreData
import Foundation

struct RecordingDetailData {
    let recording: RecordingInfo
    let segments: [TranscriptSegmentModel]
    let enhanced: EnhancedTranscriptPayload?
    let summary: SummaryPayload?
}

final class RecordingRepository {
    static let shared = RecordingRepository()

    private let context: NSManagedObjectContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(context: NSManagedObjectContext = PersistenceController.shared.viewContext) {
        self.context = context
    }

    func save(recording: RecordingInfo) {
        context.performAndWait {
            let object = recordingObject(id: recording.id) ?? insert("Recording")
            write(recording, to: object)
            saveContext()
        }
    }

    func update(_ recording: RecordingInfo) {
        save(recording: recording)
    }

    func update(status: PipelineStatus, for id: UUID) {
        context.performAndWait {
            guard let object = recordingObject(id: id) else { return }
            object.setValue(status.rawValue, forKey: "status")
            saveContext()
        }
    }

    func updateTitle(_ title: String?, for id: UUID) {
        context.performAndWait {
            guard let object = recordingObject(id: id) else { return }
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            object.setValue(trimmed?.isEmpty == true ? nil : trimmed, forKey: "title")
            saveContext()
        }
    }

    func deleteRecording(id: UUID, removeMediaFiles: Bool = true) {
        context.performAndWait {
            guard let object = recordingObject(id: id) else { return }
            let recording = readRecording(object)
            context.delete(object)
            saveContext()

            guard removeMediaFiles else { return }
            [recording?.audioURL, recording?.videoURL].compactMap { $0 }.forEach { url in
                guard url.isFileURL else { return }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func appendSegments(_ segments: [TranscriptSegmentModel], to recording: RecordingInfo) {
        context.performAndWait {
            guard let recordingObject = recordingObject(id: recording.id) else { return }
            let old = recordingObject.mutableSetValue(forKey: "segments")
            old.removeAllObjects()

            for segment in segments {
                let object = insert("TranscriptSegment")
                object.setValue(segment.id, forKey: "id")
                object.setValue(Int16(segment.index), forKey: "index")
                object.setValue(segment.text, forKey: "text")
                object.setValue(segment.timestamp, forKey: "timestamp")
                object.setValue(segment.label.rawValue, forKey: "label")
                object.setValue(segment.confidence, forKey: "confidence")
                object.setValue(nil, forKey: "cleanedText")
                object.setValue(recordingObject, forKey: "recording")
                old.add(object)
            }
            saveContext()
        }
    }

    func saveEnhancement(_ payload: EnhancedTranscriptPayload, to recording: RecordingInfo) {
        context.performAndWait {
            guard let recordingObject = recordingObject(id: recording.id) else { return }
            var cleanByIndex: [Int: String] = [:]
            for clean in payload.clean {
                cleanByIndex[clean.index] = clean.text
            }
            let segments = managedObjects(from: recordingObject.value(forKey: "segments"))
            for segment in segments {
                let index = Int(segment.value(forKey: "index") as? Int16 ?? 0)
                segment.setValue(cleanByIndex[index], forKey: "cleanedText")
            }

            let object = (recordingObject.value(forKey: "enhanced") as? NSManagedObject) ?? insert("EnhancedTranscript")
            object.setValue(UUID(), forKey: "id")
            object.setValue(encode(payload.polished), forKey: "polishedJSON")
            object.setValue(recordingObject, forKey: "recording")
            recordingObject.setValue(object, forKey: "enhanced")
            saveContext()
        }
    }

    func saveSummary(_ payload: SummaryPayload, to recording: RecordingInfo) {
        context.performAndWait {
            guard let recordingObject = recordingObject(id: recording.id) else { return }
            let object = (recordingObject.value(forKey: "summary") as? NSManagedObject) ?? insert("Summary")
            object.setValue(UUID(), forKey: "id")
            object.setValue(payload.overview, forKey: "overview")
            object.setValue(encode(payload.actionItems), forKey: "actionItemsJSON")
            object.setValue(encode(payload.decisions), forKey: "decisionsJSON")
            object.setValue(encode(payload.keyPoints), forKey: "keyPointsJSON")
            object.setValue(Date(), forKey: "generatedAt")
            object.setValue(recordingObject, forKey: "recording")
            recordingObject.setValue(object, forKey: "summary")
            saveContext()
        }
    }

    func fetchRecordings() -> [RecordingInfo] {
        var output: [RecordingInfo] = []
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Recording")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            output = ((try? context.fetch(request)) ?? []).compactMap(readRecording)
        }
        return output
    }

    func fetchDetail(id: UUID) -> RecordingDetailData? {
        var detail: RecordingDetailData?
        context.performAndWait {
            guard let recordingObject = recordingObject(id: id), let recording = readRecording(recordingObject) else { return }
            let segmentObjects = managedObjects(from: recordingObject.value(forKey: "segments"))
                .sorted { Int($0.value(forKey: "index") as? Int16 ?? 0) < Int($1.value(forKey: "index") as? Int16 ?? 0) }
            let segments = segmentObjects.compactMap(readSegment)
            let enhanced = readEnhanced(recordingObject.value(forKey: "enhanced") as? NSManagedObject, segmentObjects: segmentObjects)
            let summary = readSummary(recordingObject.value(forKey: "summary") as? NSManagedObject)
            detail = RecordingDetailData(recording: recording, segments: segments, enhanced: enhanced, summary: summary)
        }
        return detail
    }

    private func recordingObject(id: UUID) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Recording")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func insert(_ entity: String) -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
    }

    private func write(_ recording: RecordingInfo, to object: NSManagedObject) {
        object.setValue(recording.id, forKey: "id")
        object.setValue(recording.title, forKey: "title")
        object.setValue(recording.tag.rawValue, forKey: "tag")
        object.setValue(recording.createdAt, forKey: "createdAt")
        object.setValue(recording.duration, forKey: "duration")
        object.setValue(recording.audioURL?.absoluteString ?? "", forKey: "audioURL")
        object.setValue(recording.videoURL?.absoluteString, forKey: "videoURL")
        object.setValue(recording.status.rawValue, forKey: "status")
    }

    private func readRecording(_ object: NSManagedObject) -> RecordingInfo? {
        guard let id = object.value(forKey: "id") as? UUID else { return nil }
        let title = object.value(forKey: "title") as? String
        let tagRaw = object.value(forKey: "tag") as? String ?? SessionTag.meeting.rawValue
        let statusRaw = object.value(forKey: "status") as? String ?? PipelineStatus.captured.rawValue
        let audioString = object.value(forKey: "audioURL") as? String ?? ""
        let videoString = object.value(forKey: "videoURL") as? String
        return RecordingInfo(
            id: id,
            title: title,
            tag: SessionTag(rawValue: tagRaw) ?? .meeting,
            createdAt: object.value(forKey: "createdAt") as? Date ?? Date(),
            duration: object.value(forKey: "duration") as? TimeInterval ?? 0,
            audioURL: URL(string: audioString),
            videoURL: videoString.flatMap(URL.init(string:)),
            status: PipelineStatus(rawValue: statusRaw) ?? .captured
        )
    }

    private func readSegment(_ object: NSManagedObject) -> TranscriptSegmentModel? {
        guard let text = object.value(forKey: "text") as? String else { return nil }
        let index = Int(object.value(forKey: "index") as? Int16 ?? 0)
        let labelRaw = object.value(forKey: "label") as? String ?? SentenceLabel.discussion.rawValue
        return TranscriptSegmentModel(
            id: object.value(forKey: "id") as? UUID ?? UUID(),
            index: index,
            text: text,
            timestamp: object.value(forKey: "timestamp") as? TimeInterval ?? 0,
            label: SentenceLabel(rawValue: labelRaw) ?? .discussion,
            confidence: object.value(forKey: "confidence") as? Double ?? 0
        )
    }

    private func readEnhanced(_ object: NSManagedObject?, segmentObjects: [NSManagedObject]) -> EnhancedTranscriptPayload? {
        guard let object else { return nil }
        let polishedJSON = object.value(forKey: "polishedJSON") as? String ?? "[]"
        let polished: [EnhancedTranscriptPayload.TopicSection] = decode(polishedJSON) ?? []
        let clean = segmentObjects.map { segment in
            let index = Int(segment.value(forKey: "index") as? Int16 ?? 0)
            let text = (segment.value(forKey: "cleanedText") as? String) ??
                (segment.value(forKey: "text") as? String) ?? ""
            return EnhancedTranscriptPayload.CleanSegment(index: index, text: text)
        }
        return EnhancedTranscriptPayload(clean: clean, polished: polished)
    }

    private func readSummary(_ object: NSManagedObject?) -> SummaryPayload? {
        guard let object else { return nil }
        return SummaryPayload(
            overview: object.value(forKey: "overview") as? String ?? "",
            actionItems: decode(object.value(forKey: "actionItemsJSON") as? String ?? "[]") ?? [],
            decisions: decode(object.value(forKey: "decisionsJSON") as? String ?? "[]") ?? [],
            keyPoints: decode(object.value(forKey: "keyPointsJSON") as? String ?? "[]") ?? []
        )
    }

    private func managedObjects(from value: Any?) -> [NSManagedObject] {
        if let set = value as? Set<NSManagedObject> { return Array(set) }
        if let set = value as? NSSet { return set.compactMap { $0 as? NSManagedObject } }
        return []
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    private func decode<T: Decodable>(_ json: String) -> T? {
        try? decoder.decode(T.self, from: Data(json.utf8))
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        do { try context.save() } catch { NSLog("Core Data save error: \(error)") }
    }
}
