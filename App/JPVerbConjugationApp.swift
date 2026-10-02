import SwiftUI
import SwiftData
import WidgetKit
import os
import VerbKit

@main
struct JPVerbConjugationApp: App {
    @State private var networkMonitor: NetworkMonitor
    @State private var verbStore: VerbStore
    @State private var furiganaStore: FuriganaStore
    @State private var quizHistory: QuizHistoryStore
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""

    init() {
        let container = Self.makeModelContainer()
        let context = ModelContext(container)
        let fetcher = GitHubVerbFetcher.githubMain()
        let syncState = UserDefaultsSyncStateStore()
        let monitor = NetworkMonitor()
        _networkMonitor = State(initialValue: monitor)
        _verbStore = State(initialValue: VerbStore(
            syncService: VerbSyncService(fetcher: fetcher, syncState: syncState),
            persisting: SwiftDataVerbPersisting(modelContext: context),
            networkMonitor: monitor,
            grammarSyncService: GrammarSyncService(fetcher: fetcher, syncState: syncState),
            grammarPersisting: SwiftDataGrammarPersisting(modelContext: context)
        ))
        _furiganaStore = State(initialValue: FuriganaStore(
            syncService: FuriganaSyncService(fetcher: fetcher, syncState: syncState),
            persisting: SwiftDataFuriganaPersisting(modelContext: context)
        ))
        _quizHistory = State(initialValue: QuizHistoryStore(
            persisting: SwiftDataQuizHistoryPersisting(modelContext: context)
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(verbStore)
                .environment(furiganaStore)
                .environment(quizHistory)
                .task {
                    networkMonitor.start()
                    await verbStore.start()
                }
                // Any change to the verb data (first sync, Try Again, network-return retry,
                // a later update) refreshes the widgets.
                .onChange(of: verbStore.verbs) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                .onChange(of: verbStore.grammarPoints) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                .onChange(of: hiddenLevelsRaw) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                .task {
                    // Independent of the verb sync: furigana is an enhancement.
                    await furiganaStore.start()
                }
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(verbStore)
                .environment(quizHistory)
        }
        #endif
    }

    /// Falls back to an in-memory (non-persistent) store rather than
    /// crashing if the App Group container is unavailable — this can
    /// only happen from a signing/entitlement misconfiguration, which is
    /// a dev-time bug per the spec, not a scenario to build recovery UI
    /// for. One log line is enough. If even the in-memory store can't be
    /// created there is nothing left to run on, so that still stops the app.
    private static func makeModelContainer() -> ModelContainer {
        do {
            return try VerbModelContainer.make()
        } catch {
            Logger(subsystem: "dev.martinloeseth.jpverbconjugation", category: "persistence")
                .error("VerbModelContainer.make() failed (\(error, privacy: .private)); falling back to an in-memory store. Check the App Group entitlement and DEVELOPMENT_TEAM in project.yml.")
            do {
                return try VerbModelContainer.makeInMemory()
            } catch {
                fatalError("Could not create even an in-memory model container: \(error)")
            }
        }
    }
}
