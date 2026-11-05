import AVFoundation
import Observation
import Speech
import VerbKit

/// The Sentence lens's live mic (#147): the microphone into `SpeechAnalyzer` with
/// `SpeechTranscriber` (ja-JP), or `DictationTranscriber` where the device has no
/// `SpeechTranscriber`. Never `SFSpeechRecognizer`, which for ja-JP isn't on device.
///
/// The mic is gated in order: the locale is supported, the model is installed (a one-time
/// download through `AssetInventory`), and the microphone and speech permissions are
/// granted. Every gate has its own state, so the screen can explain it; typing and pasting
/// never wait on any of them.
///
/// Audio stays in memory: buffers go from the input tap straight to the analyzer and are
/// never written or sent. Only finalised text reaches `onFinal`; volatile text is shown
/// but never added to the sentence, so highlights don't flicker.
@MainActor
@Observable
final class LiveTranscriber {
    enum State: Equatable {
        case checking
        /// No Japanese transcriber on this device (or in this simulator).
        case unavailable
        /// Supported, but the model isn't installed yet.
        case needsModel
        case downloading(Double)
        case offline
        case downloadFailed
        /// Ready once the learner allows the microphone and speech recognition.
        case needsPermission
        case denied
        case ready
        case starting
        case listening
        /// The last session couldn't start or broke off; the mic can be tried again.
        case failed(String)
    }

    enum Engine {
        case speech
        case dictation
    }

    private(set) var state: State = .checking
    private(set) var engine: Engine?
    /// The words heard but not settled yet, shown in the secondary colour.
    private(set) var volatileText = ""

    var isListening: Bool { state == .listening }
    /// The mic button works in these states; the others explain why it doesn't.
    var canListen: Bool {
        switch state {
        case .needsPermission, .ready, .listening, .failed: true
        default: false
        }
    }

    /// Receives each finalised segment.
    @ObservationIgnored var onFinal: (String) -> Void = { _ in }

    @ObservationIgnored private var module: (any SpeechModule)?
    @ObservationIgnored private var locale: Locale?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var input: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private let network = NetworkMonitor()

    static let language = Locale(identifier: "ja-JP")

    init() {
        network.start()
    }

    // MARK: Gates

    /// Finds the transcriber and walks the gates as far as they go without asking anything.
    func check() async {
        state = .checking
        guard let (module, engine, locale) = await Self.makeModule() else {
            state = .unavailable
            return
        }
        self.module = module
        self.engine = engine
        self.locale = locale
        switch await AssetInventory.status(forModules: [module]) {
        case .installed:
            await reserve()
            state = permissionState()
        case .supported:
            state = .needsModel
        case .downloading:
            // Another download is under way (from an earlier visit): follow it.
            await downloadModel()
        case .unsupported:
            state = .unavailable
        @unknown default:
            state = .unavailable
        }
    }

    /// `SpeechTranscriber` where the device has it, else `DictationTranscriber` with
    /// punctuation; nil when neither supports Japanese.
    private static func makeModule() async -> (any SpeechModule, Engine, Locale)? {
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language) {
            return (SpeechTranscriber(locale: locale, preset: .progressiveTranscription), .speech, locale)
        }
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: language) {
            let transcriber = DictationTranscriber(
                locale: locale, contentHints: [], transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults], attributeOptions: []
            )
            return (transcriber, .dictation, locale)
        }
        return nil
    }

    /// Downloads and installs the Japanese model, with progress, then reserves it so the
    /// system doesn't remove it to free space.
    func downloadModel() async {
        guard let module else { return }
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else {
                // Nothing to download: it's installed.
                await reserve()
                state = permissionState()
                return
            }
            state = .downloading(request.progress.fractionCompleted)
            let progress = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(request.progress.fractionCompleted)
                }
            }
            defer { progress.cancel() }
            try await request.downloadAndInstall()
            await reserve()
            state = permissionState()
        } catch {
            state = network.isConnected ? .downloadFailed : .offline
        }
    }

    private func reserve() async {
        guard let locale else { return }
        _ = try? await AssetInventory.reserve(locale: locale)
    }

    private func permissionState() -> State {
        let microphone = AVAudioApplication.shared.recordPermission
        let speech = SFSpeechRecognizer.authorizationStatus()
        if microphone == .denied || speech == .denied || speech == .restricted { return .denied }
        if microphone == .granted && speech == .authorized { return .ready }
        return .needsPermission
    }

    /// Asks for both: #143 couldn't confirm whether live capture enforces speech
    /// recognition as well as the microphone.
    private func requestPermissions() async -> Bool {
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard microphone else { return false }
        return await Self.requestSpeechAuthorization() == .authorized
    }

    /// Off the main actor: the callback arrives on a background queue.
    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    // MARK: Listening

    func toggle() async {
        if isListening {
            await stop()
        } else {
            await start()
        }
    }

    /// Starts listening. The analyzer is running (and has been fed half a second of
    /// silence) before the state says "Listening", so the learner's first word is never
    /// clipped: #154 found `DictationTranscriber` drops the first ~500 ms of audio.
    func start() async {
        switch state {
        case .needsPermission:
            guard await requestPermissions() else {
                state = .denied
                return
            }
        case .ready, .failed:
            break
        default:
            return
        }
        guard let module else { return }
        state = .starting
        volatileText = ""
        // The mic must not hear the app speaking.
        Speaker.shared.stop()
        do {
            #if os(iOS)
            try await Speaker.changeSession { session in
                try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
                try session.setActive(true)
            }
            #endif
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                throw LiveTranscriberError.noAudioFormat
            }
            let analyzer = SpeechAnalyzer(modules: [module])
            try await analyzer.prepareToAnalyze(in: format)
            let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
            if let silence = Self.silence(format: format, seconds: 0.5) {
                input.yield(AnalyzerInput(buffer: silence))
            }
            resultsTask = consumeResults(of: module)
            try await analyzer.start(inputSequence: stream)

            let audioEngine = AVAudioEngine()
            let node = audioEngine.inputNode
            let micFormat = node.outputFormat(forBus: 0)
            guard micFormat.channelCount > 0, micFormat.sampleRate > 0,
                  let converter = AVAudioConverter(from: micFormat, to: format)
            else { throw LiveTranscriberError.noMicrophone }
            node.installTap(onBus: 0, bufferSize: 4096, format: micFormat,
                            block: Self.tap(converter: converter, format: format, into: input))
            audioEngine.prepare()
            try audioEngine.start()

            self.analyzer = analyzer
            self.audioEngine = audioEngine
            self.input = input
            state = .listening
        } catch {
            await tearDown(finalize: false)
            state = .failed(error.localizedDescription)
        }
    }

    /// Stops listening; the last words heard are finalised first, so Play and the
    /// highlights see them.
    func stop() async {
        guard state == .listening else { return }
        await tearDown(finalize: true)
        state = permissionState()
    }

    private func tearDown(finalize: Bool) async {
        if let audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        input?.finish()
        input = nil
        if let analyzer {
            if finalize {
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            } else {
                await analyzer.cancelAndFinishNow()
            }
        }
        analyzer = nil
        // The results end once the analyzer has finished.
        await resultsTask?.value
        resultsTask = nil
        volatileText = ""
        #if os(iOS)
        try? await Speaker.changeSession { session in
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }

    private func consumeResults(of module: any SpeechModule) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                if let transcriber = module as? SpeechTranscriber {
                    for try await result in transcriber.results {
                        self?.receive(String(result.text.characters), isFinal: result.isFinal)
                    }
                } else if let transcriber = module as? DictationTranscriber {
                    for try await result in transcriber.results {
                        self?.receive(String(result.text.characters), isFinal: result.isFinal)
                    }
                }
            } catch {
                // A broken-off session ends its results; the state says so via `start`/`stop`.
            }
        }
    }

    private func receive(_ text: String, isFinal: Bool) {
        if isFinal {
            volatileText = ""
            onFinal(text)
        } else {
            volatileText = text
        }
    }

    // MARK: Audio

    /// Silent audio in the analyzer's format.
    nonisolated private static func silence(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        for audio in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            if let data = audio.mData { memset(data, 0, Int(audio.mDataByteSize)) }
        }
        return buffer
    }

    /// The input tap: each mic buffer converted to the analyzer's format and passed on. Built
    /// off the main actor, since the audio thread calls it.
    nonisolated private static func tap(
        converter: AVAudioConverter, format: AVAudioFormat, into input: AsyncStream<AnalyzerInput>.Continuation
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let ratio = format.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, converted.frameLength > 0 {
                input.yield(AnalyzerInput(buffer: converted))
            }
        }
    }
}

private enum LiveTranscriberError: LocalizedError {
    case noAudioFormat
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .noAudioFormat: "The speech model has no audio format for this device."
        case .noMicrophone: "No microphone is available."
        }
    }
}
