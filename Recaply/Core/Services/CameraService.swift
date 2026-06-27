import Foundation
import AVFoundation

/// Failures surfaced by optional camera capture.
enum CameraError: Error {
    /// The user has not granted camera access (or explicitly denied it).
    case notAuthorized
    /// The `AVCaptureSession` could not be configured (no camera, input rejected, …).
    case configurationFailed
}

/// Optional front-camera recorder.
///
/// Wraps an `AVCaptureSession` + `AVCaptureMovieFileOutput` to write an `.mp4` to the
/// app's Documents directory as `cam-<uuid>.mp4`. Singleton; the capture state machine
/// calls `start()` when the user has the camera toggle on and `stop()` on record stop.
///
/// `start()` is synchronous and throws if access is missing or configuration fails.
/// `stop()` returns the intended output URL immediately; the file is finalized
/// asynchronously via the recording delegate, which then stops the session. Callers
/// that read the file (the Phase 5 pipeline) should do so shortly after capture.
final class CameraService {
    static let shared = CameraService()

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(
        label: "cn.edu.njxzc.Recaply.camera.session", qos: .userInitiated
    )
    private let delegate = MovieRecorderDelegate()

    /// The URL being recorded to for the current take; `nil` when idle or misconfigured.
    private var fileURL: URL?
    /// Guards one-time `beginConfiguration`/`commitConfiguration` of inputs + outputs.
    private var configured = false

    private init() {
        delegate.onFinish = { [weak self] _ in
            self?.handleRecordingFinish()
        }
    }

    // MARK: - Authorization

    /// Requests camera access if undetermined, or returns the current state. Mirrors the
    /// FitnessApp permission flow. Safe to call on every toggle.
    func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    // MARK: - Capture

    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CameraError.notAuthorized
        }

        var started = false
        // Configure + start on the dedicated session queue for a deterministic contract:
        // when `start()` returns, recording has begun (or it threw).
        sessionQueue.sync {
            self.configureSessionIfNeeded()
            guard !self.session.inputs.isEmpty, !self.movieOutput.isRecording else { return }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            let url = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("cam-\(UUID().uuidString).mp4")
            self.fileURL = url
            self.movieOutput.startRecording(to: url, recordingDelegate: self.delegate)
            started = true
        }

        guard started else { throw CameraError.configurationFailed }
    }

    func stop() -> URL? {
        let url = fileURL
        fileURL = nil
        // Finalization is async: the delegate stops the session once the .mp4 is sealed.
        sessionQueue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
        return url
    }

    // MARK: - Session configuration

    /// Builds a front-camera input + movie file output. Runs once; idempotent.
    private func configureSessionIfNeeded() {
        guard !configured else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        let hasInput: Bool
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            hasInput = true
        } else {
            hasInput = false
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                // Match the selfie preview the user expects from a front camera.
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
        configured = hasInput
    }

    /// Invoked from the recording delegate once the take is sealed (or failed).
    private func handleRecordingFinish() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
}

// MARK: - Recording delegate

/// Receives `AVCaptureMovieFileOutput` completion callbacks on a system queue and
/// forwards them to `CameraService` so the session can be torn down only after the
/// `.mp4` is fully written.
private final class MovieRecorderDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    var onFinish: ((Error?) -> Void)?

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // Phase 1 only logs finalization failures; the Phase 5 pipeline validates the file.
        if let error {
            print("[CameraService] recording finished with error: \(error)")
        }
        onFinish?(error)
    }
}
