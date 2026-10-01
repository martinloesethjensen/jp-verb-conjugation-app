import SwiftUI
import VerbKit

/// Which levels a search covers. Per search: it returns to `mine` when the search text is cleared and
/// never changes the saved setting.
enum LevelScope: Hashable {
    case mine, all
}

/// Adds the "My levels / All levels" scope bar only when `isActive`; otherwise the modifier is absent.
private struct LevelScopeBar: ViewModifier {
    let isActive: Bool
    @Binding var scope: LevelScope

    @ViewBuilder func body(content: Content) -> some View {
        if isActive {
            content.searchScopes($scope) {
                Text("My levels").tag(LevelScope.mine)
                Text("All levels").tag(LevelScope.all)
            }
        } else {
            content
        }
    }
}

extension View {
    func levelScopeBar(isActive: Bool, scope: Binding<LevelScope>) -> some View {
        modifier(LevelScopeBar(isActive: isActive, scope: scope))
    }
}

/// Last row of a result list: items in hidden levels also match the search.
struct HiddenMatchesRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(count) more in hidden levels — **Search all levels**")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

/// Replaces the plain empty state when the visible levels have no match but hidden ones do.
struct NoMatchInLevelsView: View {
    let summary: String
    let hiddenCount: Int
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No match in \(summary)", systemImage: "magnifyingglass")
        } description: {
            Text("\(hiddenCount) in other levels")
        } actions: {
            Button("All levels", action: action)
        }
    }
}
