import SwiftUI
import SwiftData
import VerbKit

@main
struct JPVerbConjugationApp: App {
    @State private var networkMonitor: NetworkMonitor
    @State private var verbStore: VerbStore

    init() {
        let container = Self.makeModelContainer()
        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(container))
        let syncService = VerbSyncService(
            fetcher: GitHubVerbFetcher.githubMain(),
            syncState: UserDefaultsSyncStateStore()
        )
        let monitor = NetworkMonitor()
        _networkMonitor = State(initialValue: monitor)
        _verbStore = State(initialValue: VerbStore(syncService: syncService, persisting: persisting, networkMonitor: monitor))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(verbStore)
                .task {
                    networkMonitor.start()
                    await verbStore.start()
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
