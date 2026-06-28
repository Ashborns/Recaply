import AVFoundation
import Foundation
import Speech

final class LiveTranscriptionService {
    static let shared = LiveTranscriptionService()

    var onTranscript: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var locale: Locale?
    private var isRunning = false
    private var committedTranscript = ""
    private var currentTranscript = ""
    private var rotationWorkItem: DispatchWorkItem?
    private var taskGeneration = 0
    private let appendQueue = DispatchQueue(label: "recaply.live-transcription")
    private let rotationInterval: TimeInterval = 55

    private init() {}

    func start(locale: Locale = Locale(identifier: "id-ID")) async -> Bool {
        await start(locales: [locale])
    }

    func start(locales: [Locale]) async -> Bool {
        stop()
        let authorized = await TranscriptionService.shared.requestAuthorization()
        guard authorized else { return false }

        let candidates = locales.isEmpty ? [Locale(identifier: "id-ID"), Locale(identifier: "en-US")] : locales
        guard let selected = candidates.compactMap({ locale -> (Locale, SFSpeechRecognizer)? in
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { return nil }
            return (locale, recognizer)
        }).first else {
            return false
        }

        self.locale = selected.0
        let request = SFSpeechAudioBufferRecognitionRequest()
        configure(request)
        self.recognizer = selected.1
        self.request = request
        self.isRunning = true
        self.committedTranscript = ""
        self.currentTranscript = ""
        startRecognitionTask()
        scheduleRotation()
        return true
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stop() {
        rotationWorkItem?.cancel()
        rotationWorkItem = nil
        isRunning = false
        appendQueue.sync {
            commitCurrentTranscript()
            request?.endAudio()
            taskGeneration += 1
        }
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        locale = nil
        onTranscript = nil
        currentTranscript = ""
        committedTranscript = ""
    }

    private func configure(_ request: SFSpeechAudioBufferRecognitionRequest) {
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = SpeechRecognitionPreferences.prefersOnDevice
    }

    private func startRecognitionTask() {
        guard let recognizer, let request else { return }
        taskGeneration += 1
        let generation = taskGeneration
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if error != nil {
                self.appendQueue.async { [weak self] in
                    guard let self, generation == self.taskGeneration else { return }
                    self.rotateRecognitionTask()
                }
                return
            }

            let text = result?.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }
            self.appendQueue.async { [weak self] in
                guard let self, generation == self.taskGeneration else { return }
                self.currentTranscript = text
                self.publishTranscript()
                if result?.isFinal == true {
                    self.rotateRecognitionTask()
                }
            }
        }
    }

    private func scheduleRotation() {
        rotationWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.rotateRecognitionTask()
        }
        rotationWorkItem = item
        appendQueue.asyncAfter(deadline: .now() + rotationInterval, execute: item)
    }

    private func rotateRecognitionTask() {
        appendQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.commitCurrentTranscript()
            self.request?.endAudio()
            self.taskGeneration += 1
            self.task?.cancel()

            guard let locale = self.locale,
                  let recognizer = SFSpeechRecognizer(locale: locale),
                  recognizer.isAvailable else {
                self.publishTranscript()
                return
            }

            let nextRequest = SFSpeechAudioBufferRecognitionRequest()
            self.configure(nextRequest)
            self.recognizer = recognizer
            self.request = nextRequest
            self.startRecognitionTask()
            self.scheduleRotation()
            self.publishTranscript()
        }
    }

    private func commitCurrentTranscript() {
        let trimmed = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if committedTranscript.isEmpty {
            committedTranscript = trimmed
        } else if !committedTranscript.hasSuffix(trimmed) {
            committedTranscript += " " + trimmed
        }
        currentTranscript = ""
    }

    private func publishTranscript() {
        let pieces = [committedTranscript, currentTranscript]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let fullText = pieces.joined(separator: " ")
        guard !fullText.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onTranscript?(fullText)
        }
    }
}
