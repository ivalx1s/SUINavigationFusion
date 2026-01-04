import SwiftUI

/// A preference key used to propagate a scroll/content offset to the top navigation bar.
///
/// This is an intentionally low-level building block: the library does not ship a dedicated `ScrollView` wrapper,
/// because apps often have their own scroll containers. Instead, you emit a `CGPoint` from inside your scroll view
/// (typically via `GeometryReader`) and the top bar can react (e.g. fade background based on offset).
///
/// Design constraint:
/// This preference key is designed to be written by a single, dedicated emitter per screen. With a single emitter,
/// SwiftUI propagates the value without needing to merge multiple values, so `reduce` is intentionally a no-op.
public struct PositionObservingViewPreferenceKey: SwiftUI.PreferenceKey {
    public static var defaultValue: CGPoint { .zero }
    
    public static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        // Intentionally a no-op.
        //
        // Design note:
        // This preference key is meant to be written by a single, dedicated
        // scroll-view hook per screen. With a single emitter, SwiftUI propagates
        // the value without needing to combine multiple values via `reduce`.
        //
        // If multiple emitters are introduced in the same subtree (nested scroll
        // views, overlays, etc.), define merge semantics here (e.g. last-wins,
        // minY-wins) so preference propagation remains deterministic.
    }
}
