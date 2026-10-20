import SwiftUI
import VerbKit

/// What the Counters detail column shows. `focus` lands a counter page on one number.
enum CounterDestination: Hashable {
    case group(CounterGroup)
    case counter(Counter, focus: CounterNumber?)
    case all
}

/// The Counters tab: the groups grid and search in the sidebar, a group table, counter page or
/// the full list in the detail column. Moving from a group table to a counter pushes inside the
/// detail stack.
struct CountersTab: View {
    @Binding var destination: CounterDestination?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let onSettings: () -> Void

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            CountersHomeView(destination: $destination, column: $preferredColumn, onSettings: onSettings)
        } detail: {
            NavigationStack {
                if let destination {
                    CounterDestinationView(destination: destination)
                        .navigationDestination(for: CounterDestination.self) {
                            CounterDestinationView(destination: $0)
                        }
                } else {
                    ContentUnavailableView("Choose a Group", systemImage: "square.grid.2x2")
                }
            }
            // A new choice in the sidebar starts a fresh stack.
            .id(destination)
        }
    }
}

/// The page for one destination. The counter page replaces its placeholder in the next task.
struct CounterDestinationView: View {
    let destination: CounterDestination

    var body: some View {
        switch destination {
        case let .group(group):
            GroupTableView(group: group)
        case let .counter(counter, _):
            Text(counter.counter)
                .navigationTitle(counter.counter)
        case .all:
            CounterListView()
        }
    }
}
