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

    @ObservationIgnored private var currentText: String?

    var hasJapaneseVoice: Bool { voice != nil }

    override init() {
        let japanese = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "ja-JP" }
        voice = japanese.max { $0.quality.rawValue < $1.quality.rawValue }
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        guard let spoken = SpeechText.spoken(text), let voice else { return }
        if synthesizer.isSpeaking, currentText == spoken {
            stop()
            return
        }
        stop()
        currentText = spoken
        activateSession()
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = voice
        let raw = UserDefaults.appGroup.string(forKey: "speechSpeed") ?? SpeechSpeed.normal.rawValue
        utterance.rate = (SpeechSpeed(rawValue: raw) ?? .normal).rate
        synthesizer.speak(utterance)
    }

    func stop() {
        currentText = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func activateSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        #endif
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finished = utterance.speechString
        Task { @MainActor in
            if Speaker.shared.currentText == finished { Speaker.shared.currentText = nil }
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let cancelled = utterance.speechString
        Task { @MainActor in
            if Speaker.shared.currentText == cancelled { Speaker.shared.currentText = nil }
        }
    }
}
