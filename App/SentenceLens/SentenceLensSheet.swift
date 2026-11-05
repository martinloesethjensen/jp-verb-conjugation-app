import SwiftUI
import VerbKit
#if os(iOS)
import UIKit
#endif

/// A request to open the Sentence lens, optionally with a sentence to start from.
struct SentenceLensRequest: Identifiable {
    let id = UUID()
    var text: String = ""
}

/// The Sentence lens (#147): type, paste, dictate or say a Japanese sentence, see its verbs
/// highlighted, and tap one to learn its form and flip it one step. Opened from the Verbs
/// toolbar and the "Find verbs…" text action. Typing and pasting need no permissions; the
/// live mic is optional and explains every state it can be in.
struct SentenceLensSheet: View {
    let request: SentenceLensRequest
    @Environment(FormLookupStore.self) private var store: FormLookupStore?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let store {
            SentenceLensScreen(request: request, store: store)
        } else {
            NavigationStack {
                ContentUnavailableView("Loading the verbs", systemImage: "hourglass")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        }
    }
}

private struct SentenceLensScreen: View {
    @State private var lens: SentenceLensModel
    @State private var transcriber = LiveTranscriber()
    @AppStorage("sentenceLensShowLabels", store: .appGroup) private var showLabels = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openRoute) private var openRoute
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var fieldFocused: Bool

    init(request: SentenceLensRequest, store: FormLookupStore) {
        _lens = State(initialValue: SentenceLensModel(store: store, text: request.text))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    input
                    LiveMicPanel(transcriber: transcriber, onPaste: paste)
                    transcript
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Sentence lens")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("Options", systemImage: "ellipsis") {
                        Toggle("Show labels", systemImage: "character", isOn: $showLabels)
                    }
                }
            }
        }
        .sheet(item: $lens.selected) { item in
            LensSpanSheet(lens: lens, item: item, onPlay: play)
                .presentationDetents([.medium, .large])
        }
        .environment(\.openRoute, OpenRouteAction { route in
            dismiss()
            openRoute(route)
        })
        .task {
            transcriber.onFinal = { [lens] segment in
                lens.appendTranscript(segment)
                announce(segment)
            }
            await transcriber.check()
            if lens.isBlank { fieldFocused = true }
        }
        // The mic never runs behind another app, or after the lens closes.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await transcriber.stop() } }
        }
        .onChange(of: lens.selected?.id) { _, id in
            if id != nil { Task { await transcriber.stop() } }
        }
        .onDisappear { Task { await transcriber.stop() } }
    }

    // MARK: Input

    private var input: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Type or paste a Japanese sentence", text: $lens.text, axis: .vertical)
                .font(.title3)
                .lineLimit(2...6)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .focused($fieldFocused)
                .accessibilityLabel("Sentence")
            // Side by side, or stacked at the accessibility text sizes.
            let buttons = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            buttons {
                PasteButton(payloadType: String.self) { strings in
                    let text = strings.first ?? ""
                    Task { @MainActor in paste(text) }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                if !lens.isBlank {
                    Button("Clear", systemImage: "xmark.circle") {
                        lens.text = ""
                        fieldFocused = true
                    }
                    .buttonStyle(.glass)
                }
            }
            .font(.subheadline)
            Label("System dictation: tap the mic on the keyboard. It follows your iPhone's dictation settings.", systemImage: "keyboard")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formCard()
    }

    private func paste(_ text: String) {
        lens.text = text
        fieldFocused = false
    }

    // MARK: Transcript

    @ViewBuilder
    private var transcript: some View {
        let items = lens.items
        if lens.isBlank && transcriber.volatileText.isEmpty {
            Text("Type, paste or say a sentence to see its verbs. Tap a verb to see its form and change it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(items.isEmpty ? "No verbs found" : items.count == 1 ? "1 verb" : "\(items.count) verbs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(sentenceSummary(count: items.count))
                    .accessibilityAddTraits(.isHeader)
                if !lens.isBlank {
                    LensTranscriptView(segments: lens.segments, showLabels: showLabels) { item in
                        lens.selected = item
                    }
                }
                if !transcriber.volatileText.isEmpty {
                    // Not settled yet: never highlighted, and never announced.
                    Text(transcriber.volatileText)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                if items.isEmpty && !lens.isBlank {
                    Text("The app knows the verbs in its table and the endings its lessons teach.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !items.isEmpty {
                    UnderlineKey(highlights: Set(items.map(\.highlight)), hasAmbiguous: items.contains { $0.status == .ambiguous })
                }
            }
            .formCard()
        }
    }

    /// The heading VoiceOver reads before the verbs: the count and the whole sentence.
    private func sentenceSummary(count: Int) -> String {
        let verbs = count == 0 ? "No verbs found" : count == 1 ? "1 verb" : "\(count) verbs"
        return lens.isBlank ? verbs : "\(verbs) in: \(lens.sentence)"
    }

    // MARK: Speech

    /// Stops recognition first, so the mic never hears the app speaking.
    private func play(_ text: String) {
        Task {
            await transcriber.stop()
            Speaker.shared.speak(text, restart: true)
        }
    }

    /// A finalised segment, read politely after whatever VoiceOver is saying.
    private func announce(_ segment: String) {
        var announcement = AttributedString(segment)
        announcement.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(announcement).post()
    }
}

/// What each underline in the transcript means, for the kinds shown.
private struct UnderlineKey: View {
    let highlights: Set<FormLookup.Highlight>
    let hasAmbiguous: Bool

    private static let order: [FormLookup.Highlight] = [.basic, .chain, .voice, .notInApp]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Self.order.filter(highlights.contains), id: \.self) { highlight in
                HStack(spacing: 8) {
                    LensUnderline(highlight: highlight)
                        .frame(width: 28, height: 5)
                    Text(highlight.keyLabel)
                }
            }
            if hasAmbiguous {
                HStack(spacing: 8) {
                    Text("?")
                        .font(.caption.weight(.heavy))
                        .frame(width: 28)
                    Text("More than one reading: tap to choose")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// The live mic and everything that can stand in its way: no Japanese model on the device,
/// the one-time model download, permissions, and being offline. Each state says what to do
/// instead, and typing and pasting always work.
private struct LiveMicPanel: View {
    let transcriber: LiveTranscriber
    let onPaste: (String) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
            if transcriber.state != .unavailable && transcriber.state != .checking {
                Label("Recognised on this iPhone. Audio is never stored or sent.", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formCard()
    }

    @ViewBuilder
    private var content: some View {
        switch transcriber.state {
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                Text("Checking live listening…")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .unavailable:
            Label("Live listening isn't available on this device. Type, paste or use System dictation.", systemImage: "mic.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .needsModel:
            Button {
                Task { await transcriber.downloadModel() }
            } label: {
                Label("Download Japanese speech model (one-time)", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            Text(modelSize + " from Apple. After that, listening works offline.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading(let fraction):
            ProgressView(value: fraction) {
                Text("Downloading Japanese speech model…")
                    .font(.subheadline)
            } currentValueLabel: {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
            }
        case .offline:
            Label("You're offline. Connect to the internet to download the speech model.", systemImage: "wifi.slash")
                .font(.subheadline)
            retryButton
        case .downloadFailed:
            Label("The speech model couldn't be downloaded.", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
            retryButton
        case .denied:
            Label("Microphone or speech recognition is off for Verb Table, so live listening can't start.", systemImage: "mic.slash")
                .font(.subheadline)
            HStack(spacing: 8) {
                if let url = Self.settingsURL {
                    Button("Open Settings", systemImage: "gear") { openURL(url) }
                        .buttonStyle(.glass)
                }
                PasteButton(payloadType: String.self) { strings in
                    let text = strings.first ?? ""
                    Task { @MainActor in onPaste(text) }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
            }
            .font(.subheadline)
        case .needsPermission, .ready, .starting, .listening, .failed:
            micToggle
            if case .failed(let message) = transcriber.state {
                Text("Listening stopped: \(message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if transcriber.state == .needsPermission {
                Text("The first time, you'll be asked to allow the microphone and speech recognition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if transcriber.engine == .dictation {
                Text("Using the dictation model: this device doesn't have the newer speech model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var micToggle: some View {
        let listening = transcriber.isListening
        return Toggle(isOn: Binding(
            get: { listening },
            set: { _ in Task { await transcriber.toggle() } }
        )) {
            Label {
                Text(listening ? "Listening… tap to stop" : transcriber.state == .starting ? "Starting…" : "Listen")
            } icon: {
                Image(systemName: listening ? "waveform" : "mic")
                    .symbolEffect(.variableColor.iterative, isActive: listening)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.button)
        .buttonStyle(.glass)
        .disabled(transcriber.state == .starting)
        .accessibilityLabel("Live mic")
        .accessibilityValue(listening ? "Listening" : "Off")
    }

    private var retryButton: some View {
        Button("Try again", systemImage: "arrow.clockwise") {
            Task { await transcriber.downloadModel() }
        }
        .buttonStyle(.glass)
        .font(.subheadline)
    }

    /// The sizes #143 measured.
    private var modelSize: String {
        transcriber.engine == .dictation ? "About 330 MB" : "About 130 MB"
    }

    private static var settingsURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openSettingsURLString)
        #else
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        #endif
    }
}

extension View {
    /// Presents the Sentence lens for `request`, full height.
    func sentenceLensSheet(_ request: Binding<SentenceLensRequest?>) -> some View {
        sheet(item: request) { request in
            SentenceLensSheet(request: request)
                .presentationDetents([.large])
        }
    }
}
