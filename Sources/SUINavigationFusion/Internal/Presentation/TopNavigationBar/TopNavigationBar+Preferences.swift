import SwiftUI

extension View {
    /// Applies the custom top‑navigation‑bar modifier to the view.
    /// - Parameter isRoot: Pass `true` when this screen is the root of the
    ///   navigation stack so the back button is hidden automatically.
    func topNavigationBar(isRoot: Bool) -> some View {
        modifier(TopNavigationBar(isRoot: isRoot))
    }
}

struct TopNavigationBarItemView: Equatable, View {
    // `View` is main-actor-isolated in SwiftUI, but `onPreferenceChange` requires an `Equatable`
    // value and performs equality checks from a nonisolated context.
    //
    // We treat these identity fields as immutable snapshots used purely for diffing, so it's safe
    // to expose them as `nonisolated(unsafe)` for `==`.
    nonisolated(unsafe) private let id: AnyHashable
    nonisolated(unsafe) private let updateKey: AnyHashable?
    private let view: AnyView
    
    /// - Parameters:
    ///   - id: Stable identity for diffing and update coalescing.
    ///   - updateKey: Use this to force an update when `id` stays the same but the rendered content changes.
    init(id: AnyHashable, updateKey: AnyHashable? = nil, view: AnyView) {
        self.id = id
        self.updateKey = updateKey
        self.view = view
    }
    
    nonisolated static func == (lhs: TopNavigationBarItemView, rhs: TopNavigationBarItemView) -> Bool {
        lhs.id == rhs.id && lhs.updateKey == rhs.updateKey
    }
    
    var body: some View {
        view
    }
}

struct TopNavigationPrincipalView: Equatable, View {
    // See `TopNavigationBarItemView` for why these fields are `nonisolated(unsafe)`.
    nonisolated(unsafe) private let id: AnyHashable
    nonisolated(unsafe) private let updateKey: AnyHashable?
    private let view: AnyView
    
    /// - Parameters:
    ///   - id: Stable identity for diffing and update coalescing.
    ///   - updateKey: Use this to force an update when `id` stays the same but the rendered content changes.
    init(id: AnyHashable, updateKey: AnyHashable? = nil, view: AnyView) {
        self.id = id
        self.updateKey = updateKey
        self.view = view
    }
    
    nonisolated static func == (lhs: TopNavigationPrincipalView, rhs: TopNavigationPrincipalView) -> Bool {
        lhs.id == rhs.id && lhs.updateKey == rhs.updateKey
    }
    
    var body: some View {
        view
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

struct TopNavigationBarLeadingPreferenceKey: PreferenceKey {
    static let defaultValue: TopNavigationBarItemView? = nil
    static func reduce(value: inout TopNavigationBarItemView?, nextValue: () -> TopNavigationBarItemView?) {
        if let next = nextValue() { value = next }
    }
}

struct TopNavigationBarTrailingPrimaryPreferenceKey: PreferenceKey {
    static let defaultValue: TopNavigationBarItemView? = nil
    static func reduce(value: inout TopNavigationBarItemView?, nextValue: () -> TopNavigationBarItemView?) {
        if let next = nextValue() { value = next }
    }
}

struct TopNavigationBarTrailingSecondaryPreferenceKey: PreferenceKey {
    static let defaultValue: TopNavigationBarItemView? = nil
    static func reduce(value: inout TopNavigationBarItemView?, nextValue: () -> TopNavigationBarItemView?) {
        if let next = nextValue() { value = next }
    }
}

struct TopNavigationBarPrincipalViewPreferenceKey: PreferenceKey {
    static let defaultValue: TopNavigationPrincipalView? = nil
    static func reduce(value: inout TopNavigationPrincipalView?, nextValue: () -> TopNavigationPrincipalView?) {
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
