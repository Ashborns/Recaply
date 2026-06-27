import Foundation
import Combine

/// Capture state machine for the Record screen.
///
/// Drives the mic recorder (and optional camera) through `idle → recording → stopping`.
/// On `stop()` it assembles a `RecordingInfo` with status `.captured` and leaves the phase
/// at `.stopping` for the presentation layer to acknowledge. The Phase 5 pipeline and
/// Processing screen attach to `lastRecording` at the marked hook.
@MainActor
final class RecordViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle, recording, stopping
    }

    @Published var phase: Phase = .idle
    /// Mic loudness `0...1` for the live waveform, polled while recording.
    @Published var level: Float = 0
    @Published var elapsed: TimeInterval = 0
    @Published var tag: SessionTag = .meeting
    @Published var title: String = ""
    @Published var cameraOn: Bool = false
    @Published var lastRecording: RecordingInfo?
    @Published var liveTranscript: String = ""
    @Published var liveCaptionStatus: String = "Live captions appear while you speak."
    /// Friendly message surfaced inline when capture fails to start.
    @Published var startError: String?

    private let recorder: RecordingProviding
    private let camera: CameraProviding
    private let liveTranscriber: LiveTranscriptionService
    private var levelTimer: Timer?
    private var recordingStartedAt: Date?

    init(recorder: RecordingProviding = RecordingService.shared,
         camera: CameraProviding = CameraService.shared,
         liveTranscriber: LiveTranscriptionService = .shared) {
        self.recorder = recorder
        self.camera = camera
        self.liveTranscriber = liveTranscriber
    }

    // MARK: - Capture lifecycle

    func start(tag: SessionTag, title: String?) async throws {
        // Guard against a double-start leaking a second timer / second capture.
        guard phase == .idle else { return }
        self.tag = tag
        self.title = title ?? ""
        self.level = 0
        self.elapsed = 0
        self.lastRecording = nil
        self.liveTranscript = ""
        self.liveCaptionStatus = "Listening for speech…"
        self.startError = nil
        self.recordingStartedAt = Date()

        if let recordingService = recorder as? RecordingService {
            let liveReady = await liveTranscriber.start(locale: RecaplySpeechLanguage.selected.primaryLocale)
            if liveReady {
                liveTranscriber.onTranscript = { [weak self] text in
                    Task { @MainActor [weak self] in
                        self?.liveTranscript = text
                        self?.liveCaptionStatus = "Live transcript"
                    }
                }
                recordingService.setAudioBufferConsumer { [weak liveTranscriber] buffer in
                    liveTranscriber?.append(buffer)
                }
            } else {
                liveCaptionStatus = "Live captions unavailable; final transcript still runs after stop."
                recordingService.setAudioBufferConsumer(nil)
            }
        } else {
            liveCaptionStatus = "Live captions disabled for this recorder."
        }

        do {
            _ = try recorder.start()
            if cameraOn { try await camera.start() }
        } catch {
            (recorder as? RecordingService)?.setAudioBufferConsumer(nil)
            liveTranscriber.stop()
            throw error
        }

        phase = .recording
        // Schedule + add to `.common` so the waveform keeps animating during tracking
        // touch (scroll/gesture) instead of stalling in the default run-loop mode.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            // Keep UI state updates on the main actor for Swift concurrency checks.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.level = self.recorder.currentLevel
                self.elapsed = Date().timeIntervalSince(self.recordingStartedAt ?? Date())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    func stop() {
        levelTimer?.invalidate()
        levelTimer = nil

        // Set `.stopping` first so observers (and tests) see the transition before the
        // recorder is torn down. The presentation layer flips back to `.idle` via
        // `acknowledgeCapture()`; Phase 5 will instead launch the pipeline here.
        phase = .stopping
        level = 0

        let (url, duration) = (try? recorder.stop()) ?? (URL(fileURLWithPath: "/dev/null"), 0)
        (recorder as? RecordingService)?.setAudioBufferConsumer(nil)
        liveTranscriber.stop()
        elapsed = duration
        liveCaptionStatus = liveTranscript.isEmpty ? "Final transcript will be generated from audio." : "Live transcript captured."
        recordingStartedAt = nil
        // `stop()` returns the intended URL immediately; the `.mp4` is sealed async.
        // Phase 5 must `await camera.waitForFinalization()` before reading videoURL.
        let videoURL = cameraOn ? camera.stop() : nil
        lastRecording = RecordingInfo(
            id: UUID(),
            title: title.isEmpty ? nil : title,
            tag: tag,
            createdAt: Date(),
            duration: duration,
            audioURL: url,
            videoURL: videoURL,
            status: .captured,
            liveTranscript: liveTranscript.isEmpty ? nil : liveTranscript
        )

        // MARK: - Phase 5 hook
        // The Pipeline + Processing screen attach here on `lastRecording`.
        // `acknowledgeCapture()` is the placeholder reset the UI calls for now; in Phase 5
        // this becomes `PipelineCoordinator.run(lastRecording)` and a Processing presentation.
    }

    /// Presentation hook: return to idle after the UI has acknowledged the capture.
    /// Leaves `lastRecording` intact so Phase 5 can pick it up from this same state.
    func acknowledgeCapture() {
        guard phase == .stopping else { return }
        phase = .idle
    }

    /// Powers the camera toggle: requests access and reverts the toggle when denied,
    /// keeping the request flow inside the service layer (views stay framework-free).
    func enableCamera() async -> Bool {
        let granted = await camera.requestAccess()
        if !granted { cameraOn = false }
        return granted
    }
}
