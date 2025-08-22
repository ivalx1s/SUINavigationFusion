import SwiftUI

public struct PositionObservingViewPreferenceKey: SwiftUI.PreferenceKey {
    public static var defaultValue: CGPoint { .zero }
    
    public static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        // No-op
    }
}
