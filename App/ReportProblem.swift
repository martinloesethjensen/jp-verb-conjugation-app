import SwiftUI
import VerbKit

/// The versions line sent with a report: the app build and the data version each
/// file last synced, so a maintainer knows what the reporter was looking at.
enum ReportContext {
    static func versions() -> String {
        let state = UserDefaultsSyncStateStore()
        return IssueReportURL.versions(
            app: UserDefaultsSyncStateStore.currentBuild,
            verbs: state.lastSyncedManifest()?.version,
            grammar: state.lastSyncedGrammarManifest()?.version,
            furigana: state.lastSyncedFuriganaManifest()?.version
        )
    }
}

/// Opens the prefilled GitHub report form. `item` names what is being reported
/// ("Verb: たべる (食べる)"); leave it empty for a general report.
struct ReportProblemButton: View {
    let item: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Report a problem", systemImage: "exclamationmark.bubble") {
            openURL(IssueReportURL.report(item: item, versions: ReportContext.versions()))
        }
    }
}
