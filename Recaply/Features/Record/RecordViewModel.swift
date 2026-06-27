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
    @Published var tag: SessionTag = .meeting
    @Published var title: String = ""
    @Published var cameraOn: Bool = false
    @Published var lastRecording: RecordingInfo?
    /// Friendly message surfaced inline when capture fails to start.
    @Published var startError: String?

    private let recorder: RecordingProviding
    private let camera: CameraProviding
    private var levelTimer: Timer?

    init(recorder: RecordingProviding = RecordingService.shared,
         camera: CameraProviding = CameraService.shared) {
        self.recorder = recorder
        self.camera = camera
    }

    // MARK: - Capture lifecycle

    func start(tag: SessionTag, title: String?) async throws {
        // Guard against a double-start leaking a second timer / second capture.
        guard phase == .idle else { return }
        self.tag = tag
        self.title = title ?? ""
        self.level = 0
        self.lastRecording = nil
        self.startError = nil

        _ = try recorder.start()
        if cameraOn { try await camera.start() }

        phase = .recording
        // Schedule + add to `.common` so the waveform keeps animating during tracking
        // touch (scroll/gesture) instead of stalling in the default run-loop mode.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            // Read directly on the main run loop — no per-tick `Task` hop.
            self?.level = self?.recorder.currentLevel ?? 0
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
            status: .captured
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
