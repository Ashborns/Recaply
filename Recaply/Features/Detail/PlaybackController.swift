import AVFoundation
import Foundation

@MainActor
final class PlaybackController: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL?) {
        stopTimer()
        player?.stop()
        player = nil
        currentTime = 0
        duration = 0
        isPlaying = false

        guard let url else { return }
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.prepareToPlay()
            player = audio
            duration = audio.duration
        } catch {
            NSLog("Playback load error: \(error)")
        }
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(seconds, player.duration))
        player.currentTime = clamped
        currentTime = clamped
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                self.duration = player.duration
                if !player.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
