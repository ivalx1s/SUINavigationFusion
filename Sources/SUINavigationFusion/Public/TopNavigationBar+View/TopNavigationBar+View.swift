import SwiftUI

public extension View {
    /// Sets a plain‑string title for the top navigation bar.
    /// Call on the *outermost* view of the screen.
    @ViewBuilder
    func topNavigationBarTitle(_ title: String) -> some View {
        preference(key: TopNavigationBarTitlePreferenceKey.self, value: title)
    }
    
    /// Sets a fully formatted `Text` view as the title.
    /// Use this when you need multiline or richly styled titles.
    ///
    /// > Styling note: Any modifiers you apply directly to the `Text`
    /// > (e.g. `.font()`, `.foregroundStyle()`, `.fontWeight()`)
    /// > this **ignores**
    /// > the corresponding values in `TopNavigationBarConfiguration`
    /// > (`titleFont`, `titleFontWeight`, `titleFontColor`).
    @ViewBuilder
    func topNavigationBarTitle(_ text: @escaping () -> Text) -> some View {
        preference(key: TopNavigationBarTitleTextPreferenceKey.self, value: text())
    }
    
    /// Sets a secondary (subtitle) line beneath the title.
    @ViewBuilder
    func topNavigationBarSubtitle(_ title: String) -> some View {
        preference(key: TopNavigationBarSubtitlePreferenceKey.self, value: title)
    }
    
    /// Sets a fully styled `Text` view as the subtitle.
    /// Any font or color modifiers applied to the `Text`
    /// override `subtitleFont`, `subtitleFontWeight`, and `subtitleFontColor`
    /// from `TopNavigationBarConfiguration`.
    @ViewBuilder
    func topNavigationBarSubtitle(_ text: @escaping () -> Text) -> some View {
        preference(key: TopNavigationBarSubtitleTextPreferenceKey.self, value: text())
    }
    
    /// Controls visibility of the back button for this screen.
    /// - Parameter hides: `true` (default) hides the back button.
    @ViewBuilder
    func topNavigationBarHidesBackButton(_ hides: Bool = true) -> some View {
        preference(key: TopNavigationBarHidesBackButtonPreferenceKey.self, value: hides)
    }
    
    /// Supplies a custom leading‑side view (e.g. avatar or logo).
    @ViewBuilder
    func topNavigationBarLeading<Content: View>(id: (any Hashable)? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        preference(key: TopNavigationBarLeadingPreferenceKey.self,
                   value: TopNavigationBarItemView(id: id?.hashValue, view: AnyView(content())))
    }
    
    /// Supplies a custom trailing‑side view (e.g. action buttons).
    @ViewBuilder
    func topNavigationBarTrailingPrimary<Content: View>(id: (any Hashable)? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        preference(key: TopNavigationBarTrailingPrimaryPreferenceKey.self,
                   value: TopNavigationBarItemView(id: id?.hashValue, view: AnyView(content())))
    }
    
    /// Supplies an additional trailing‑side view (e.g. secondary action).
    /// Useful when two buttons are needed on the right.
    @ViewBuilder
    func topNavigationBarTrailing<Content: View>(
        id: (any Hashable)? = nil,
        position: TrailingContentPosition = .primary,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        switch position {
        case .primary:
            preference(
                key: TopNavigationBarTrailingPrimaryPreferenceKey.self,
                value: TopNavigationBarItemView(id: id?.hashValue, view: AnyView(content()))
            )
        case .secondary:
            preference(
                key: TopNavigationBarTrailingSecondaryPreferenceKey.self,
                value: TopNavigationBarItemView(id: id?.hashValue, view: AnyView(content()))
            )
        }
    }
}
