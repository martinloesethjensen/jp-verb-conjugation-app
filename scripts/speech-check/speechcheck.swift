// Speech check (#143): Apple's on-device ja-JP transcription, from audio files.
//
// Built by run.sh (swiftc), not part of the app. macOS 26+ only.
//
//   speechcheck status                     availability, installed / reserved locales, asset status
//   speechcheck install                    reserve ja-JP and download the SpeechTranscriber and
//                                          DictationTranscriber models (one-time, system-wide)
//   speechcheck transcribe ENGINE OUT.json FILE...
//                                          ENGINE = st (SpeechTranscriber) | dt (DictationTranscriber)
//   speechcheck tokenize < lines.txt       CFStringTokenizer tokens + kana readings as JSON
//
// Everything runs on device: SpeechAnalyzer reads the file, no audio leaves the Mac.

import AVFoundation
import Foundation
import Speech

let ja = Locale(identifier: "ja-JP")

func stderr(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

func makeST() -> SpeechTranscriber {
    SpeechTranscriber(locale: ja, transcriptionOptions: [],
                      reportingOptions: [.alternativeTranscriptions],
                      attributeOptions: [.transcriptionConfidence])
}

func makeDT() -> DictationTranscriber {
    DictationTranscriber(locale: ja, contentHints: [], transcriptionOptions: [.punctuation],
                         reportingOptions: [.alternativeTranscriptions],
                         attributeOptions: [.transcriptionConfidence])
}

func status() async {
    print("SpeechTranscriber.isAvailable:", SpeechTranscriber.isAvailable)
    print("SpeechTranscriber installed:", await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }.sorted())
    print("DictationTranscriber installed:", await DictationTranscriber.installedLocales.map { $0.identifier(.bcp47) }.sorted())
    print("AssetInventory status ja-JP, SpeechTranscriber:", await AssetInventory.status(forModules: [makeST()]))
    print("AssetInventory status ja-JP, DictationTranscriber:", await AssetInventory.status(forModules: [makeDT()]))
    let auth: String
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: auth = "authorized"
    case .denied: auth = "denied"
    case .restricted: auth = "restricted"
    case .notDetermined: auth = "notDetermined"
    @unknown default: auth = "unknown"
    }
    print("Speech recognition authorization (this process):", auth)
    print("Reserved locales:", await AssetInventory.reservedLocales.map { $0.identifier(.bcp47) },
          "max:", AssetInventory.maximumReservedLocales)
}

func install() async throws {
    let reserved = try await AssetInventory.reserve(locale: ja)
    print("reserve(ja-JP):", reserved)
    for (name, module) in [("SpeechTranscriber", makeST() as any SpeechModule), ("DictationTranscriber", makeDT())] {
        let t0 = Date()
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else {
            print("\(name): already installed")
            continue
        }
        let progress = request.progress
        let watcher = Task {
            while !Task.isCancelled {
                stderr(String(format: "  \(name): %.0f%%  (%lld / %lld bytes)", progress.fractionCompleted * 100,
                              progress.completedUnitCount, progress.totalUnitCount))
                try? await Task.sleep(for: .seconds(5))
            }
        }
        try await request.downloadAndInstall()
        watcher.cancel()
        print(String(format: "\(name): installed in %.1f s; progress total units %lld (bytes, when the system reports them)",
                     Date().timeIntervalSince(t0), progress.totalUnitCount))
    }
    await status()
}

struct Transcript: Codable {
    var file: String
    var engine: String
    var text: String
    var alternatives: [String]
    var confidence: Double?
    var audioSeconds: Double
    var wallSeconds: Double        // analyzer start -> last final result, file input
    var firstResultSeconds: Double?
    var error: String?
}

func meanConfidence(_ s: AttributedString) -> Double? {
    var total = 0.0, weight = 0.0
    for run in s.runs {
        if let c = run.transcriptionConfidence {
            let n = Double(s[run.range].characters.count)
            total += c * n; weight += n
        }
    }
    return weight > 0 ? total / weight : nil
}

func transcribe(engine: String, url: URL) async -> Transcript {
    var out = Transcript(file: url.lastPathComponent, engine: engine, text: "", alternatives: [],
                         confidence: nil, audioSeconds: 0, wallSeconds: 0, firstResultSeconds: nil)
    do {
        let file = try AVAudioFile(forReading: url)
        out.audioSeconds = Double(file.length) / file.processingFormat.sampleRate
        let t0 = Date()
        var texts: [AttributedString] = []
        var alts: [String] = []
        var first: Double?
        if engine == "st" {
            let t = makeST()
            let collector = Task { () -> ([AttributedString], [String], Double?) in
                var texts: [AttributedString] = [], alts: [String] = [], first: Double?
                for try await r in t.results where r.isFinal {
                    if first == nil { first = Date().timeIntervalSince(t0) }
                    texts.append(r.text)
                    alts.append(contentsOf: r.alternatives.dropFirst().map { String($0.characters) })
                }
                return (texts, alts, first)
            }
            let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [t], finishAfterFile: true)
            (texts, alts, first) = try await collector.value
            withExtendedLifetime(analyzer) {}
        } else {
            let t = makeDT()
            let collector = Task { () -> ([AttributedString], [String], Double?) in
                var texts: [AttributedString] = [], alts: [String] = [], first: Double?
                for try await r in t.results where r.isFinal {
                    if first == nil { first = Date().timeIntervalSince(t0) }
                    texts.append(r.text)
                    alts.append(contentsOf: r.alternatives.dropFirst().map { String($0.characters) })
                }
                return (texts, alts, first)
            }
            let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [t], finishAfterFile: true)
            (texts, alts, first) = try await collector.value
            withExtendedLifetime(analyzer) {}
        }
        out.wallSeconds = Date().timeIntervalSince(t0)
        out.firstResultSeconds = first
        let joined = texts.reduce(AttributedString()) { $0 + $1 }
        out.text = String(joined.characters)
        out.confidence = meanConfidence(joined)
        out.alternatives = alts
    } catch {
        out.error = "\(error)"
    }
    return out
}

func tokenize() {
    var out: [[String: Any]] = []
    while let line = readLine() {
        let cf = line as CFString
        let t = CFStringTokenizerCreate(nil, cf, CFRangeMake(0, CFStringGetLength(cf)),
                                        kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale)
        var toks: [[String: Any]] = []
        while CFStringTokenizerAdvanceToNextToken(t) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(t)
            let w = (line as NSString).substring(with: NSRange(location: r.location, length: r.length))
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(t, kCFStringTokenizerAttributeLatinTranscription) as? String ?? ""
            toks.append(["s": r.location, "w": w, "kana": latin.applyingTransform(.latinToHiragana, reverse: false) ?? ""])
        }
        out.append(["text": line, "tokens": toks])
    }
    let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "status":
    await status()
case "install":
    do { try await install() } catch { stderr("install failed: \(error)"); exit(1) }
case "transcribe" where args.count >= 4:
    let a = Array(args)
    let engine = a[1], outPath = a[2]
    guard engine == "st" || engine == "dt" else { stderr("engine must be st or dt"); exit(2) }
    if engine == "st" && !SpeechTranscriber.isAvailable {
        stderr("SpeechTranscriber is not available on this machine"); exit(1)
    }
    let installed = engine == "st" ? await SpeechTranscriber.installedLocales : await DictationTranscriber.installedLocales
    guard installed.contains(where: { $0.identifier(.bcp47) == "ja-JP" }) else {
        stderr("The ja-JP model isn't installed. Run: python3 scripts/speech-check/speech_check.py install"); exit(1)
    }
    var results: [Transcript] = []
    for path in a[3...] {
        let r = await transcribe(engine: engine, url: URL(fileURLWithPath: path))
        stderr("  [\(engine)] \(r.file): \(r.error ?? r.text)")
        results.append(r)
    }
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try! enc.encode(results).write(to: URL(fileURLWithPath: outPath))
case "tokenize":
    tokenize()
default:
    stderr("usage: speechcheck status | install | transcribe st|dt OUT.json FILE... | tokenize < lines")
    exit(2)
}
