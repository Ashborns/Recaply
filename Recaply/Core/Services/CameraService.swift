import Foundation
import AVFoundation
import os

/// Structured logging for camera capture. File-private so both `CameraService` and its
/// recording delegate can use it without leaking the symbol.
private let logger = Logger(subsystem: "cn.edu.njxzc.Recaply", category: "Camera")

/// Failures surfaced by optional camera capture.
enum CameraError: Error {
    /// The user has not granted camera access (or explicitly denied it).
    case notAuthorized
    /// The `AVCaptureSession` could not be configured (no camera, input rejected, …).
    case configurationFailed
}

/// Abstraction over optional front-camera capture so `RecordViewModel` can be tested
/// with a stub (and so Phase 5 can substitute a fake when wiring the pipeline).
protocol CameraProviding {
    /// Requests camera access if undetermined; returns the resulting authorization state.
    func requestAccess() async -> Bool
    /// Configure the session and begin recording a take. Suspends (off the main thread)
    /// while the session is configured on its serial queue, then returns once recording
    /// has begun. Throws on missing access or configuration failure.
    func start() async throws
    /// Returns the intended output URL immediately and triggers non-blocking finalize.
    /// The `.mp4` is NOT yet sealed when this returns.
    func stop() -> URL?
    /// Suspends until the `AVCaptureMovieFileOutput` delegate has sealed the `.mp4`
    /// (or determines there is nothing to wait for). No-op if the camera was off.
    func waitForFinalization() async
}

/// Optional front-camera recorder.
///
/// Wraps an `AVCaptureSession` + `AVCaptureMovieFileOutput` to write an `.mp4` to the
/// app's Documents directory as `cam-<uuid>.mp4`. Singleton; the capture state machine
/// calls `start()` when the user has the camera toggle on and `stop()` on record stop.
///
/// `start()` is `async throws`: the session configuration + `startRunning()` run on a
/// dedicated serial queue (`sessionQueue`) so the main thread is never blocked. `stop()`
/// returns the intended output URL immediately and triggers finalization asynchronously.
/// The `.mp4` is only fully written once the recording delegate's
/// `didFinishRecordingTo` callback fires; await `waitForFinalization()` to reach that
/// point before reading the file.
final class CameraService: CameraProviding {
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
    /// `true` between `stop()` issuing `stopRecording()` and the delegate sealing the
    /// file. Drives `waitForFinalization()`.
    private var finalizeExpecting = false
    /// Resumed from the recording delegate (on `sessionQueue`) to release a caller
    /// awaiting `waitForFinalization()`.
    private var finalizeContinuation: CheckedContinuation<Void, Never>?

    private init() {
        delegate.onFinish = { [weak self] error in
            self?.handleRecordingFinish(error)
        }
    }

    // MARK: - CameraProviding

    /// Requests camera access if undetermined, or returns the current state. Safe to
    /// call on every toggle.
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

    func start() async throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CameraError.notAuthorized
        }

        // Configure + start on the dedicated serial session queue, but via a
        // continuation so the calling (main) thread suspends instead of blocking on
        // `sessionQueue.sync`. When `start()` returns, recording has begun or it threw.
        // The error flows back through the continuation's value rather than a captured
        // `var` (which would trip concurrent-mutation warnings in a `@Sendable` closure).
        let thrownError: CameraError? = await withCheckedContinuation { continuation in
            sessionQueue.async {
                self.configureSessionIfNeeded()
                // No usable camera input → configuration failed.
                guard !self.session.inputs.isEmpty else {
                    continuation.resume(returning: CameraError.configurationFailed)
                    return
                }
                // Already recording a take → idempotent no-op.
                guard !self.movieOutput.isRecording else {
                    continuation.resume(returning: nil)
                    return
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }

                let url = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("cam-\(UUID().uuidString).mp4")
                self.fileURL = url
                self.finalizeExpecting = false
                self.movieOutput.startRecording(to: url, recordingDelegate: self.delegate)
                continuation.resume(returning: nil)
            }
        }
        if let thrownError { throw thrownError }
    }

    func stop() -> URL? {
        let url = fileURL
        // Finalization is async: trigger `stopRecording()` (non-blocking) and let the
        // delegate seal the `.mp4`. `fileURL` is cleared by the delegate so a caller
        // can still resolve `waitForFinalization()` against this take.
        sessionQueue.async {
            self.finalizeExpecting = (url != nil) && self.movieOutput.isRecording
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
        return url
    }

    /// Phase 5's pipeline MUST `await camera.waitForFinalization()` before reading the
    /// video file returned by `stop()`, otherwise the `.mp4` may not be sealed yet.
    /// Safe to call when the camera was off (returns immediately).
    func waitForFinalization() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                // Serialized against the delegate handler on this same queue.
                if !self.finalizeExpecting {
                    // Nothing pending: already sealed, or the camera was never recording.
                    continuation.resume()
                    return
                }
                self.finalizeContinuation = continuation
            }
        }
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

    /// Invoked from the recording delegate once the take is sealed (or failed). Resumes
    /// any caller awaiting `waitForFinalization()`. Runs on `sessionQueue`.
    private func handleRecordingFinish(_ error: Error?) {
        sessionQueue.async {
            self.finalizeExpecting = false
            self.fileURL = nil
            if self.session.isRunning {
                self.session.stopRunning()
            }
            if let continuation = self.finalizeContinuation {
                self.finalizeContinuation = nil
                continuation.resume()
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
            logger.error("recording finished with error: \(error.localizedDescription, privacy: .public)")
        }
        onFinish?(error)
    }
}
