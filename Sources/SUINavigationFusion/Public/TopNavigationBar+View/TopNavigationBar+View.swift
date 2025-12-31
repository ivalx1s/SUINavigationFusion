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
    ///
    /// - Parameters:
    ///   - id: Stable identity for this item. If `nil`, a stable per-view fallback id is generated.
    ///   - updateKey: Provide this when the rendered content can change while `id` stays the same
    ///     (e.g. badge count). Changing `updateKey` forces the bar to refresh the item.
    @ViewBuilder
    func topNavigationBarLeading<Content: View>(
        id: AnyHashable? = nil,
        updateKey: AnyHashable? = nil,
        @ViewBuilder _ content: @escaping () -> Content
    ) -> some View {
        modifier(TopNavigationBarItemPreferenceWriter(id: id, updateKey: updateKey, preference: .leading, content: content))
    }
    
    /// Supplies a custom trailing‑side view (e.g. action buttons).
    ///
    /// - Parameters:
    ///   - id: Stable identity for this item. If `nil`, a stable per-view fallback id is generated.
    ///   - updateKey: Provide this when the rendered content can change while `id` stays the same.
    @ViewBuilder
    func topNavigationBarTrailingPrimary<Content: View>(
        id: AnyHashable? = nil,
        updateKey: AnyHashable? = nil,
        @ViewBuilder _ content: @escaping () -> Content
    ) -> some View {
        modifier(TopNavigationBarItemPreferenceWriter(id: id, updateKey: updateKey, preference: .trailing(.primary), content: content))
    }
    
    /// Supplies an additional trailing‑side view (e.g. secondary action).
    /// Useful when two buttons are needed on the right.
    ///
    /// - Parameters:
    ///   - id: Stable identity for this item. If `nil`, a stable per-view fallback id is generated.
    ///   - updateKey: Provide this when the rendered content can change while `id` stays the same.
    ///   - position: Which trailing slot to use.
    @ViewBuilder
    func topNavigationBarTrailing<Content: View>(
        id: AnyHashable? = nil,
        updateKey: AnyHashable? = nil,
        position: TrailingContentPosition = .primary,
        @ViewBuilder _ content: @escaping () -> Content
    ) -> some View {
        modifier(TopNavigationBarItemPreferenceWriter(id: id, updateKey: updateKey, preference: .trailing(position), content: content))
    }

    /// Supplies a custom center (principal) view for the navigation bar.
    /// When set, it replaces the default title/subtitle stack.
    ///
    /// - Parameters:
    ///   - id: Stable identity for this view. If `nil`, a stable per-view fallback id is generated.
    ///   - updateKey: Provide this when the rendered content can change while `id` stays the same.
    @ViewBuilder
    func topNavigationBarPrincipalView<Content: View>(
        id: AnyHashable? = nil,
        updateKey: AnyHashable? = nil,
        @ViewBuilder _ content: @escaping () -> Content
    ) -> some View {
        modifier(TopNavigationBarPrincipalPreferenceWriter(id: id, updateKey: updateKey, content: content))
    }

    /// Overrides the tint (accent) color used by the top navigation bar items on this screen.
    ///
    /// This affects the back button and any leading/trailing content that relies on SwiftUI tinting.
    /// Use this when you need per-screen tint because `NavigationShell` applies the bar *outside*
    /// the screen’s subtree (so a regular `.tint(...)` on the screen does not reach the bar).
    ///
    /// - Parameter color:
    ///   - `nil`: explicitly inherit tint from the surrounding SwiftUI environment (ignores configuration tint).
    ///   - non-`nil`: force this tint color for the bar items on this screen.
    @ViewBuilder
    func topNavigationBarTintColor(_ color: Color?) -> some View {
        preference(
            key: TopNavigationBarTintPreferenceKey.self,
            value: color.map(TopNavigationBarTintOverride.color) ?? .inherit
        )
    }
}

private enum TopNavigationBarItemPreference {
    case leading
    case trailing(TrailingContentPosition)
}

private struct TopNavigationBarItemPreferenceWriter<Item: View>: ViewModifier {
    let id: AnyHashable?
    let updateKey: AnyHashable?
    let preference: TopNavigationBarItemPreference
    let content: () -> Item

    // A stable fallback id for cases where the caller doesn't provide one.
    // This avoids churn compared to generating a new UUID/hash on every render.
    @State private var fallbackID = AnyHashable(UUID())

    private var resolvedID: AnyHashable { id ?? fallbackID }

    func body(content root: Content) -> some View {
        let itemView = TopNavigationBarItemView(id: resolvedID, updateKey: updateKey, view: AnyView(content()))

        switch preference {
        case .leading:
            root.preference(key: TopNavigationBarLeadingPreferenceKey.self, value: itemView)
        case let .trailing(position):
            switch position {
            case .primary:
                root.preference(key: TopNavigationBarTrailingPrimaryPreferenceKey.self, value: itemView)
            case .secondary:
                root.preference(key: TopNavigationBarTrailingSecondaryPreferenceKey.self, value: itemView)
            }
        }
    }
}

private struct TopNavigationBarPrincipalPreferenceWriter<Item: View>: ViewModifier {
    let id: AnyHashable?
    let updateKey: AnyHashable?
    let content: () -> Item

    @State private var fallbackID = AnyHashable(UUID())

    private var resolvedID: AnyHashable { id ?? fallbackID }

    func body(content root: Content) -> some View {
        root.preference(
            key: TopNavigationBarPrincipalViewPreferenceKey.self,
            value: TopNavigationPrincipalView(id: resolvedID, updateKey: updateKey, view: AnyView(content()))
        )
    }
}
