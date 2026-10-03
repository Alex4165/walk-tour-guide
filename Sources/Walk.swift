import AVFoundation
import MediaPlayer
import Observation

/// Test: while a walk is running, the headphone play button records 5 seconds
/// from the mic and plays it back — including with the phone locked.
///
/// A silent loop keeps the audio session alive so the app stays the
/// "Now Playing" app and keeps receiving headphone button presses.
@Observable
final class Walk {
    var status = "Plug in headphones and start a walk."
    var isRunning = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var silence: AVAudioPCMBuffer?
    private var recorded: [AVAudioPCMBuffer] = []
    private var isRecording = false
    private var isSetUp = false

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            status = "Microphone permission denied. Enable it in Settings."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            if !isSetUp { try setUp() }

            try engine.start()
            player.scheduleBuffer(silence!, at: nil, options: .loops, completionHandler: nil)
            player.play()

            MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "Tour Guide walk"]
            isRunning = true
            status = "Walking. Lock the phone and press the headphone button to record 5 seconds."
        } catch {
            status = "Failed to start: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        isRunning = false
        isRecording = false
        status = "Stopped."
    }

    private func setUp() throws {
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Walk", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input available."])
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // One second of silence, looped between recordings.
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate))!
        buffer.frameLength = buffer.frameCapacity
        for ch in 0..<Int(format.channelCount) {
            buffer.floatChannelData![ch].update(repeating: 0, count: Int(buffer.frameLength))
        }
        silence = buffer

        // Wired EarPods' center button usually sends togglePlayPause; handle all three to be safe.
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand] {
            command.addTarget { [weak self] _ in
                self?.buttonPressed()
                return .success
            }
        }
        isSetUp = true
    }

    private func buttonPressed() {
        guard isRunning, !isRecording else { return }
        isRecording = true
        recorded = []
        status = "Recording…"

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let copy = Self.copy(buffer) else { return }
            DispatchQueue.main.async { self?.recorded.append(copy) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.playBack()
        }
    }

    private func playBack() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        status = "Playing back…"

        // Replace the silent loop with the recording, then resume silence.
        player.stop()
        for buffer in recorded {
            player.scheduleBuffer(buffer)
        }
        player.scheduleBuffer(silence!, at: nil, options: .loops)
        player.play()
        status = "Walking. Press the headphone button to record again."
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let src = buffer.floatChannelData, let dst = out.floatChannelData else { return nil }
        out.frameLength = buffer.frameLength
        for ch in 0..<Int(buffer.format.channelCount) {
            dst[ch].update(from: src[ch], count: Int(buffer.frameLength))
        }
        return out
    }
}
