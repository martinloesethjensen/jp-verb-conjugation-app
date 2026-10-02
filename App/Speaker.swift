import AVFoundation
import Observation
import SwiftUI
import VerbKit

enum SpeechSpeed: String, CaseIterable, Identifiable {
    case normal, slow

    var id: String { rawValue }
    var label: String { self == .normal ? "Normal" : "Slow" }
    var rate: Float {
        self == .normal ? AVSpeechUtteranceDefaultSpeechRate : AVSpeechUtteranceDefaultSpeechRate * 0.7
    }
}

/// Speaks Japanese with the best installed system voice. One shared instance, so a
/// new utterance always cuts off the previous one.
@MainActor
@Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?

    static let voiceDefaultsKey = "speechVoiceID"

    var hasJapaneseVoice: Bool { !Self.japaneseVoices().isEmpty }

    /// Installed Japanese voices, best quality first. Read fresh each time so voices
    /// downloaded while the app is running show up.
    static func japaneseVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "ja-JP" }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    static func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }

    /// The voice chosen in Settings, or the best installed one when none is chosen
    /// (or the chosen one has since been removed).
    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        let voices = Self.japaneseVoices()
        let chosen = UserDefaults.appGroup.string(forKey: Self.voiceDefaultsKey) ?? ""
        return voices.first { $0.identifier == chosen } ?? voices.first
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Tapping the text that is already being spoken stops it, unless `restart` is set
    /// (the quiz always wants the new answer spoken).
    func speak(_ text: String, restart: Bool = false) {
        guard let spoken = SpeechText.spoken(text), let voice = resolvedVoice() else { return }
        if !restart, synthesizer.isSpeaking, currentUtterance?.speechString == spoken {
            stop()
            return
        }
        cancelCurrent()
        activateSession()
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = voice
        let raw = UserDefaults.appGroup.string(forKey: "speechSpeed") ?? SpeechSpeed.normal.rawValue
        utterance.rate = (SpeechSpeed(rawValue: raw) ?? .normal).rate
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    func stop() {
        cancelCurrent()
        deactivateSessionIfIdle()
    }

    /// Cuts off the previous utterance without releasing the audio session.
    private func cancelCurrent() {
        currentUtterance = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func activateSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        #endif
    }

    private func deactivateSessionIfIdle() {
        #if os(iOS)
        guard currentUtterance == nil, !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let finished = utterance
        Task { @MainActor in
            let speaker = Speaker.shared
            if speaker.currentUtterance === finished { speaker.currentUtterance = nil }
            speaker.deactivateSessionIfIdle()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let cancelled = utterance
        Task { @MainActor in
            let speaker = Speaker.shared
            if speaker.currentUtterance === cancelled { speaker.currentUtterance = nil }
        }
    }
}
