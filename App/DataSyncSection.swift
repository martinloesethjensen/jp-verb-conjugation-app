import SwiftUI
import VerbKit

/// Settings' Data section: each data file's version and when it was last updated,
/// a plain-language note if the latest check didn't work, and Refresh data.
struct DataSyncSection: View {
    @Environment(DataSyncStatus.self) private var syncStatus

    /// A plain `Section`, so the list styles it like the others (a TimelineView around it turned it
    /// into one grey system row). The relative times redraw every minute inside their own rows.
    var body: some View {
        Section {
            ForEach(DataFile.allCases) { file in
                DataFileRow(status: syncStatus.status(for: file))
            }
            Button {
                Task { await syncStatus.refresh() }
            } label: {
                HStack {
                    Text(syncStatus.isRefreshing ? "Checking for new data…" : "Refresh data")
                    Spacer()
                    if syncStatus.isRefreshing {
                        ProgressView()
                    }
                }
            }
            .disabled(syncStatus.isRefreshing)
        } header: {
            Text("Data")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                TimelineView(.everyMinute) { _ in Text(footer) }
                Text(KanjiDisplay.settingsCredit)
            }
        }
        .paperRow()
    }

    private var footer: String {
        let auto = "Data updates automatically when the app opens."
        guard let checked = syncStatus.lastChecked else { return auto }
        return "\(auto) Last checked \(checked.formatted(.relative(presentation: .named)))."
    }
}

private struct DataFileRow: View {
    @Environment(\.palette) private var palette
    let status: DataFileStatus

    private var versionText: String {
        guard let version = status.version else { return "Not downloaded yet" }
        return status.isBundled ? "Bundled · v\(version)" : "Version \(version)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.file.displayName)
                Spacer()
                Text(versionText)
                    .foregroundStyle(palette.muted)
                    .monospacedDigit()
            }
            if let updated = status.lastUpdated {
                // Redrawn every minute so "Updated 2 minutes ago" doesn't go stale while Settings is open.
                TimelineView(.everyMinute) { _ in
                    Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                        .font(.footnote)
                        .foregroundStyle(palette.muted)
                }
            }
            if let message = status.problemMessage {
                Label(message, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
