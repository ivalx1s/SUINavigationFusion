import SwiftUI

extension View {
    /// Applies the custom top‑navigation‑bar modifier to the view.
    /// - Parameter isRoot: Pass `true` when this screen is the root of the
    ///   navigation stack so the back button is hidden automatically.
    func topNavigationBar(isRoot: Bool) -> some View {
        modifier(TopNavigationBar(isRoot: isRoot))
    }
}

// MARK: - Bar item models (PreferenceKey payloads)

/// An equatable snapshot of a bar item.
///
/// Important:
/// `onPreferenceChange` requires an `Equatable` payload and SwiftUI may perform equality checks
/// from a nonisolated context. We compare identity fields only and treat the view payload as an
/// opaque value used exclusively for rendering on the main actor.
struct TopNavigationBarItem: Equatable {
    nonisolated(unsafe) private let id: AnyHashable
    nonisolated(unsafe) private let updateKey: AnyHashable?
    let view: AnyView

    init(id: AnyHashable, updateKey: AnyHashable? = nil, view: AnyView) {
        self.id = id
        self.updateKey = updateKey
        self.view = view
    }

    nonisolated static func == (lhs: TopNavigationBarItem, rhs: TopNavigationBarItem) -> Bool {
        lhs.id == rhs.id && lhs.updateKey == rhs.updateKey
    }
}

/// An equatable snapshot of the principal (center) bar content.
struct TopNavigationBarPrincipal: Equatable {
    nonisolated(unsafe) private let id: AnyHashable
    nonisolated(unsafe) private let updateKey: AnyHashable?
    let view: AnyView

    init(id: AnyHashable, updateKey: AnyHashable? = nil, view: AnyView) {
        self.id = id
        self.updateKey = updateKey
        self.view = view
    }

    nonisolated static func == (lhs: TopNavigationBarPrincipal, rhs: TopNavigationBarPrincipal) -> Bool {
        lhs.id == rhs.id && lhs.updateKey == rhs.updateKey
    }
}

// MARK: - Bar item renderers

/// Renders a bar item snapshot.
///
/// Note: this type is intentionally **not** `Equatable`.
/// Some SwiftUI diffing paths treat `Equatable` views as update-skippable, which can prevent
/// environment-driven updates (like changing tint) from reaching bar button content.
struct TopNavigationBarItemContent: View {
    let item: TopNavigationBarItem
    let itemTintColor: Color

    var body: some View {
        item.view
            // Bar items should behave like native `UINavigationBar` buttons.
            //
            // We apply the *resolved* tint color directly instead of relying solely on `.tint(...)`
            // propagation. This is more reliable for type-erased `AnyView` payloads and complex
            // compositions where tint updates may not reach image-based labels deterministically.
            //
            // Callers can still override colors inside their custom content when needed.
            .foregroundStyle(itemTintColor)
            .foregroundColor(itemTintColor)
            .topNavigationBarItemTapTarget()
    }
}

// MARK: - Hit testing

private let topNavigationBarItemTapTargetMinHeight: CGFloat = 44
private let topNavigationBarItemTapTargetHorizontalPadding: CGFloat = 12

private extension View {
    /// Expands tappable area for bar items without changing layout.
    ///
    /// This solves two common issues for toolbar content:
    /// 1) Small icons are hard to hit.
    /// 2) Stroked shapes (e.g. `Circle().stroke(...)`) can be tappable only on the visible stroke.
    ///
    /// The implementation keeps the visual layout unchanged by applying a negative padding after
    /// setting `contentShape`, while still using a rectangular hit target.
    func topNavigationBarItemTapTarget() -> some View {
        frame(minHeight: topNavigationBarItemTapTargetMinHeight)
            .padding(.horizontal, topNavigationBarItemTapTargetHorizontalPadding)
            .contentShape(Rectangle())
            .padding(.horizontal, -topNavigationBarItemTapTargetHorizontalPadding)
    }
}

// MARK: – Preference keys that bubble ↑
struct TopNavigationBarTitlePreferenceKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) {
        if let next = nextValue() { value = next }
    }
}

struct TopNavigationBarTitleTextPreferenceKey: PreferenceKey {
    static let defaultValue: Text? = nil
    static func reduce(value: inout Text?, nextValue: () -> Text?) {
        if let next = nextValue() { value = next }
    }
}


struct TopNavigationBarSubtitlePreferenceKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) {
        if let next = nextValue() { value = next }
    }
}

struct TopNavigationBarSubtitleTextPreferenceKey: PreferenceKey {
    static let defaultValue: Text? = nil
    static func reduce(value: inout Text?, nextValue: () -> Text?) {
        if let next = nextValue() { value = next }
    }
}

struct TopNavigationBarHidesBackButtonPreferenceKey: PreferenceKey {
    static let defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

struct TopNavigationBarLeadingPreferenceKey: @MainActor PreferenceKey {
    @MainActor static let defaultValue: TopNavigationBarItem? = nil
    static func reduce(value: inout TopNavigationBarItem?, nextValue: () -> TopNavigationBarItem?) {
        if let next = nextValue() { value = next }
    }
}

struct TopNavigationBarTrailingPrimaryPreferenceKey: @MainActor PreferenceKey {
    @MainActor static let defaultValue: TopNavigationBarItem? = nil
    static func reduce(value: inout TopNavigationBarItem?, nextValue: () -> TopNavigationBarItem?) {
        if let next = nextValue() { value = next }
    }
}

struct TopNavigationBarTrailingSecondaryPreferenceKey: @MainActor PreferenceKey {
    @MainActor static let defaultValue: TopNavigationBarItem? = nil
    static func reduce(value: inout TopNavigationBarItem?, nextValue: () -> TopNavigationBarItem?) {
        if let next = nextValue() { value = next }
    }
}

struct TopNavigationBarPrincipalViewPreferenceKey: @MainActor PreferenceKey {
    @MainActor static let defaultValue: TopNavigationBarPrincipal? = nil
    static func reduce(value: inout TopNavigationBarPrincipal?, nextValue: () -> TopNavigationBarPrincipal?) {
        if let next = nextValue() { value = next }
    }
}

struct TopNavigationBarVisibilityPreferenceKey: PreferenceKey {
    static let defaultValue: [TopNavigationBar.Section: TopNavigationBar.ComponentVisibility]? = nil
    static func reduce(
        value: inout [TopNavigationBar.Section: TopNavigationBar.ComponentVisibility]?,
        nextValue: () -> [TopNavigationBar.Section: TopNavigationBar.ComponentVisibility]?
    ) {
        guard let next = nextValue() else { return }
        if value == nil {
            value = next
            return
        }
        value?.merge(next, uniquingKeysWith: { _, new in new })
    }
}
