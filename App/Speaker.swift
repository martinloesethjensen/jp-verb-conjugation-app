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
    @ObservationIgnored private let voice: AVSpeechSynthesisVoice?

    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?

    var hasJapaneseVoice: Bool { voice != nil }

    override init() {
        let japanese = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "ja-JP" }
        voice = japanese.max { $0.quality.rawValue < $1.quality.rawValue }
        super.init()
        synthesizer.delegate = self
    }

    /// Tapping the text that is already being spoken stops it, unless `restart` is set
    /// (the quiz always wants the new answer spoken).
    func speak(_ text: String, restart: Bool = false) {
        guard let spoken = SpeechText.spoken(text), let voice else { return }
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
