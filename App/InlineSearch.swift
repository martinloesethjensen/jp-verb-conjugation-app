import SwiftUI

extension View {
    /// Search field under the large title (iOS) or in the toolbar (macOS). On iOS it hides when
    /// the list scrolls and returns on pull-down; `focused` lets a toolbar button bring it back.
    @ViewBuilder func inlineSearch(
        text: Binding<String>,
        prompt: LocalizedStringKey,
        focused: FocusState<Bool>.Binding
    ) -> some View {
        #if os(iOS)
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .automatic), prompt: prompt)
            .searchFocused(focused)
        #else
        searchable(text: text, prompt: prompt)
            .searchFocused(focused)
        #endif
    }
}
