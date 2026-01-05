import SwiftUI

/// Public visibility state used by `topNavigationBarVisibility(_:for:)`.
public enum TopNavigationBarVisibility: Hashable, Codable, Sendable {
    case visible
    case hidden
}

/// Identifies a top navigation bar section that can be shown/hidden per screen.
///
/// Use `.trailingPosition(...)` to control a single trailing slot
/// (for example, hide only the `.secondary` trailing item).
public enum TopNavigationBarSection: Hashable, Codable, Sendable {
    /// The whole bar container (including safe-area inset + background).
    ///
    /// Use this for full-screen screens (video/photo detail) where you want content to extend to the top edge.
    case bar
    case leading
    case principal
    case trailing
    case trailingPosition(TrailingContentPosition)
}

public extension View {
    /// Controls visibility of navigation-bar sections for this screen.
    /// Call on the *outermost* view of the screen.
    @ViewBuilder
    func topNavigationBarVisibility(_ visibility: TopNavigationBarVisibility, for section: TopNavigationBarSection) -> some View {
        let internalVisibility: TopNavigationBar.ComponentVisibility = switch visibility {
        case .visible: .visible
        case .hidden: .hidden
        }
        
        let internalSection: TopNavigationBar.Section = switch section {
        case .bar: .bar
        case .leading: .leading
        case .principal: .principal
        case .trailing: .trailing
        case let .trailingPosition(position): .trailingPosition(position)
        }
        
        preference(
            key: TopNavigationBarVisibilityPreferenceKey.self,
            value: [internalSection: internalVisibility]
        )
    }
}
