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
/// a live RMS level for the waveform. Singleton; injected through the protocol so
/// the capture state machine stays testable off-device.
final class RecordingService: RecordingProviding {
    static let shared = RecordingService()

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var startTime: Date?
    /// Written from the audio render thread, polled by the UI timer. A torn `Float`
    /// read is visually harmless for a waveform, so no lock is used by design.
    private(set) var currentLevel: Float = 0

    private init() {}

    // MARK: - RecordingProviding

    func start() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rec-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1
        ]
        // Create the file up-front so the first input buffer is never dropped.
        file = try AVAudioFile(forWriting: url, settings: settings)
        fileURL = url

        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024) { [weak self] buffer, _ in
            guard let self else { return }
            self.currentLevel = self.rms(buffer)
            try? self.file?.write(from: buffer)
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

    // MARK: - Level metering

    /// Root-mean-square of the first channel, mapped to `0...1` for the waveform.
    private func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            sum += data[i] * data[i]
        }
        return sqrt(sum / Float(buffer.frameLength))
    }
}
