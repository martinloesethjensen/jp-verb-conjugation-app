import SwiftUI

extension View {
    /// Search field under the large title (iOS) or in the toolbar (macOS). On iOS it hides when
    /// the list scrolls and returns on pull-down; `focused` lets a toolbar button bring it back.
    /// `alwaysVisible` keeps it on screen instead (the Counters directory, where search is the way in).
    @ViewBuilder func inlineSearch(
        text: Binding<String>,
        prompt: LocalizedStringKey,
        focused: FocusState<Bool>.Binding,
        alwaysVisible: Bool = false
    ) -> some View {
        #if os(iOS)
        searchable(
            text: text, placement: .navigationBarDrawer(displayMode: alwaysVisible ? .always : .automatic),
            prompt: prompt
        )
            .searchFocused(focused)
        #else
        searchable(text: text, prompt: prompt)
            .searchFocused(focused)
        #endif
    }
}
