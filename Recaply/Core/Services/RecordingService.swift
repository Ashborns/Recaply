import Foundation
import AVFoundation

/// Abstraction over microphone capture so `RecordViewModel` can be tested with a stub.
protocol RecordingProviding {
    /// Begin capturing mic input to a sandbox file. Returns the file URL.
    func start() throws -> URL
    /// Stop capturing and finalize the file. Returns the URL and total duration.
    func stop() throws -> (url: URL, duration: TimeInterval)
    /// Current input loudness in `0...1`, sampled for the live waveform.
    var currentLevel: Float { get }
}

/// Microphone recorder built on `AVAudioEngine`.
///
/// Writes AAC inside an `.m4a` container to the app's Documents directory and exposes
/// a live perceptually-scaled level for the waveform. Singleton; injected through the
/// protocol so the capture state machine stays testable off-device.
final class RecordingService: RecordingProviding {
    static let shared = RecordingService()

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var startTime: Date?
    /// Consecutive `AVAudioFile.write` failures from the tap; once it exceeds the
    /// threshold we abort rather than silently producing an empty file.
    private var writeFailureCount: Int = 0
    /// Set when the tap self-aborts (e.g. persistent write failures) so a caller can
    /// surface the problem instead of reading a silent `.m4a`.
    private(set) var lastError: Error?
    /// Written from the audio render thread, polled by the UI timer. A torn `Float`
    /// read is visually harmless for a waveform, so no lock is used by design.
    private(set) var currentLevel: Float = 0

    private init() {}

    // MARK: - RecordingProviding

    func start() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        // Derive everything from the real input-node format. The hardware output
        // format is frequently 48000 Hz, and `AVAudioFile.write(from:)` requires
        // `buffer.format == file.processingFormat` — hardcoding 44100 here made the
        // write throw (swallowed by `try?`) and produced a header-only `.m4a`.
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rec-\(UUID().uuidString).m4a")
        // Derive settings from the real tap format so buffers match processingFormat.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount
        ]
        file = try AVAudioFile(forWriting: url, settings: settings)
        fileURL = url
        writeFailureCount = 0

        engine.inputNode.removeTap(onBus: 0)
        // Install the tap in `inputFormat` so delivered buffers are exactly the
        // file's `processingFormat`.
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.currentLevel = self.level(from: buffer)
            do {
                try self.file?.write(from: buffer)
            } catch {
                self.writeFailureCount &+= 1
                if self.writeFailureCount > 4 {
                    // Stop a bad recording rather than silently producing an empty file.
                    self.abortRecordingFromQueue()
                }
            }
        }

        try engine.start()
        startTime = Date()
        return url
    }

    func stop() throws -> (url: URL, duration: TimeInterval) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let duration = Date().timeIntervalSince(startTime ?? Date())
        let url = fileURL ?? URL(fileURLWithPath: "/dev/null")
        file = nil
        fileURL = nil
        currentLevel = 0
        return (url, duration)
    }

    // MARK: - Self-recovery

    /// Tears down a recording that is failing to persist. Safe to call from the audio
    /// render queue: no UIKit/SwiftUI, only engine + tap teardown plus a stored error
    /// the caller can read on the main thread.
    private func abortRecordingFromQueue() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        lastError = RecordingError.writeFailed
        file = nil
    }

    // MARK: - Level metering

    /// Perceptually-scaled, smoothed RMS level in `0...1`.
    ///
    /// Raw RMS for speech sits around `0.02...0.08`, which looked flat on the old
    /// waveform. We boost it into the visible range, then smooth with a fast attack /
    /// slow release so the bars stay lively instead of jittering on every sample.
    private func level(from buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return currentLevel }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return currentLevel }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let raw = sqrt(sum / Float(n))        // ~0.02–0.08 for speech
        let scaled = min(1, raw * 6.0)        // perceptual boost into 0...1
        // Fast attack, slow release so transients pop and tails ease out.
        let alpha: Float = scaled > currentLevel ? 0.6 : 0.15
        return currentLevel + (scaled - currentLevel) * alpha
    }
}

/// Surfacable capture failures (distinct from thrown `AVAudioSession`/engine errors).
enum RecordingError: Error {
    /// The tap was writing frames that never matched the file's `processingFormat`,
    /// or the file system rejected writes — recording was aborted mid-take.
    case writeFailed
}
