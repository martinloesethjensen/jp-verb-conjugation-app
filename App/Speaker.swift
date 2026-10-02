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
    /// Rate for a recorded clip, where 1 is the speed it was recorded at.
    var playbackRate: Float { self == .normal ? 1 : 0.75 }
}

/// Speaks Japanese. Text with a recorded clip bundled in the app (see
/// `scripts/generate_audio.py`) is played from the clip; everything else, and
/// everything when a specific system voice is chosen in Settings, uses the system
/// voice. One shared instance, so new speech always cuts off the previous one.
@MainActor
@Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = Speaker()

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playingText: String?

    static let voiceDefaultsKey = "speechVoiceID"

    var hasJapaneseVoice: Bool { !Self.japaneseVoices().isEmpty }

    /// True when recorded clips ship with the app, so audio works without a system voice.
    static let hasRecordedAudio: Bool = {
        !(Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: nil) ?? []).isEmpty
    }()

    private static func clipURL(for spoken: String) -> URL? {
        Bundle.main.url(forResource: SpeechText.clipName(for: spoken), withExtension: "mp3")
    }

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
        return voices.first { $0.identifier == Self.chosenVoiceID } ?? voices.first
    }

    /// The system voice picked in Settings, or empty for Automatic.
    private static var chosenVoiceID: String {
        UserDefaults.appGroup.string(forKey: voiceDefaultsKey) ?? ""
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Tapping the text that is already being spoken stops it, unless `restart` is set
    /// (the quiz always wants the new answer spoken).
    func speak(_ text: String, restart: Bool = false) {
        guard let spoken = SpeechText.spoken(text) else { return }
        // "Automatic" prefers a recorded clip; a voice picked in Settings is always used.
        let clip = Self.chosenVoiceID.isEmpty ? Self.clipURL(for: spoken) : nil
        let voice = clip == nil ? resolvedVoice() : nil
        guard clip != nil || voice != nil else { return }
        if !restart, isSpeaking(spoken) {
            stop()
            return
        }
        cancelCurrent()
        activateSession()
        let raw = UserDefaults.appGroup.string(forKey: "speechSpeed") ?? SpeechSpeed.normal.rawValue
        let speed = SpeechSpeed(rawValue: raw) ?? .normal
        if let clip, let player = try? AVAudioPlayer(contentsOf: clip) {
            player.delegate = self
            player.enableRate = true
            player.rate = speed.playbackRate
            self.player = player
            playingText = spoken
            player.play()
        } else if let voice = voice ?? resolvedVoice() {
            let utterance = AVSpeechUtterance(string: spoken)
            utterance.voice = voice
            utterance.rate = speed.rate
            currentUtterance = utterance
            synthesizer.speak(utterance)
        }
    }

    private func isSpeaking(_ spoken: String) -> Bool {
        if player?.isPlaying == true, playingText == spoken { return true }
        return synthesizer.isSpeaking && currentUtterance?.speechString == spoken
    }

    func stop() {
        cancelCurrent()
        deactivateSessionIfIdle()
    }

    /// Cuts off the previous utterance without releasing the audio session.
    private func cancelCurrent() {
        player?.stop()
        player = nil
        playingText = nil
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
        guard currentUtterance == nil, player == nil, !synthesizer.isSpeaking else { return }
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

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        nonisolated(unsafe) let finishedPlayer = finished
        Task { @MainActor in
            let speaker = Speaker.shared
            if speaker.player === finishedPlayer {
                speaker.player = nil
                speaker.playingText = nil
            }
            speaker.deactivateSessionIfIdle()
        }
    }
}
