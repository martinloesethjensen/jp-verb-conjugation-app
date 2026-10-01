import SwiftUI
import SwiftData
import WidgetKit
import VerbKit

@main
struct JPVerbConjugationApp: App {
    @State private var networkMonitor: NetworkMonitor
    @State private var verbStore: VerbStore
    @State private var furiganaStore: FuriganaStore

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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(verbStore)
                .environment(furiganaStore)
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
                .task {
                    // Independent of the verb sync: furigana is an enhancement.
                    await furiganaStore.start()
                }
        }
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }

    /// Falls back to an in-memory (non-persistent) store rather than
    /// crashing if the App Group container is unavailable — this can
    /// only happen from a signing/entitlement misconfiguration, which is
    /// a dev-time bug per the spec, not a scenario to build recovery UI
    /// for. One console log is enough.
    private static func makeModelContainer() -> ModelContainer {
        do {
            return try VerbModelContainer.make()
        } catch {
            print("⚠️ VerbModelContainer.make() failed (\(error)); falling back to an in-memory store. Check the App Group entitlement and DEVELOPMENT_TEAM in project.yml.")
            return try! VerbModelContainer.makeInMemory()
        }
    }
}
