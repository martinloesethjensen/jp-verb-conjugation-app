import SwiftUI
import VerbKit

/// Settings' Data section: each data file's version and when it was last updated,
/// a plain-language note if the latest check didn't work, and Refresh data.
struct DataSyncSection: View {
    @Environment(DataSyncStatus.self) private var syncStatus

    var body: some View {
        // Redrawn every minute so "Updated 2 minutes ago" doesn't go stale while Settings is open.
        TimelineView(.everyMinute) { _ in
            section
        }
    }

    private var section: some View {
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
            Text(footer)
        }
    }

    private var footer: String {
        let auto = "Data updates automatically when the app opens."
        guard let checked = syncStatus.lastChecked else { return auto }
        return "\(auto) Last checked \(checked.formatted(.relative(presentation: .named)))."
    }
}

private struct DataFileRow: View {
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
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let updated = status.lastUpdated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let message = status.problemMessage {
                Label(message, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
