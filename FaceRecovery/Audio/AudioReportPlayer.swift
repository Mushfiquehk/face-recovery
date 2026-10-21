import AVFoundation
import Observation

/// Reads a Daily Report aloud with the system voice. Speech is generated on the device, so
/// nothing about a scan leaves the phone to make it.
@MainActor
@Observable
final class AudioReportPlayer: NSObject {
    private(set) var isSpeaking = false

    /// Silence after each sentence. The system voice barely pauses at a full stop inside one
    /// utterance, so every sentence is its own utterance with a deliberate gap after it.
    private static let pauseBetweenSentences: TimeInterval = 0.7

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// Identifies the final utterance of the current report, so the player only reports
    /// "finished" when the whole report is done rather than after the first sentence.
    @ObservationIgnored private var lastUtterance: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ sentences: [String]) {
        isSpeaking ? stop() : speak(sentences)
    }

    func speak(_ sentences: [String]) {
        stop()
        guard !sentences.isEmpty else { return }
        // Playback category so the report is heard with the silent switch on, as with any
        // spoken audio. Failure only means the system default is used.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        let voice = Self.warmestVoice()
        let utterances = sentences.map { sentence in
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = voice
            // Slower than the default: the report is for listening, not skimming.
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            utterance.postUtteranceDelay = Self.pauseBetweenSentences
            return utterance
        }
        lastUtterance = utterances.last.map(ObjectIdentifier.init)
        isSpeaking = true
        utterances.forEach(synthesizer.speak)
    }

    /// The most natural installed voice for the user's language, so the report does not sound
    /// like a robot. Premium and Enhanced voices are chosen when the user has downloaded them
    /// (Settings > Accessibility > Spoken Content > Voices); the old novelty and Eloquence
    /// voices are skipped. The choice depends only on what is installed, never on chance.
    private static func warmestVoice() -> AVSpeechSynthesisVoice? {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier
        let natural = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.hasPrefix(language)
                && !voice.identifier.contains("speech.synthesis.voice")
                && !voice.identifier.contains("eloquence")
        }
        let best = natural.max { rank($0, region: region) < rank($1, region: region) }
        return best ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    /// Region match first, then quality, then identifier so ties break the same way each time.
    private static func rank(_ voice: AVSpeechSynthesisVoice, region: String?) -> (Int, Int, String) {
        let matchesRegion = region.map { voice.language.hasSuffix($0) } ?? false
        return (matchesRegion ? 1 : 0, voice.quality.rawValue, voice.identifier)
    }

    func stop() {
        lastUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    fileprivate func finished(_ utterance: ObjectIdentifier) {
        guard utterance == lastUtterance else { return }
        lastUtterance = nil
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension AudioReportPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }
}
