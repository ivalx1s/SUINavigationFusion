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
    private let id: Int
    private let view: AnyView
    
    init(id: Int? = nil, view: AnyView) {
        if let id {
            self.id = id
        } else {
            self.id = UUID().hashValue
        }
        self.view = view
    }
    
    nonisolated static func == (lhs: TopNavigationBarItemView, rhs: TopNavigationBarItemView) -> Bool { lhs.id == rhs.id }
    
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
