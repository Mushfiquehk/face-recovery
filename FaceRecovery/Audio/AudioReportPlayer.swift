import AVFoundation
import Observation

/// Reads a Daily Report aloud with the system voice. Speech is generated on the device, so
/// nothing about a scan leaves the phone to make it.
@MainActor
@Observable
final class AudioReportPlayer: NSObject {
    private(set) var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String) {
        isSpeaking ? stop() : speak(text)
    }

    func speak(_ text: String) {
        stop()
        // Playback category so the report is heard with the silent switch on, as with any
        // spoken audio. Failure only means the system default is used.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        // Slower than the default: the report is for listening, not skimming.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    fileprivate func finished() {
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension AudioReportPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }
}
