import SwiftUI

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
