import SwiftUI

public enum TopNavigationBarVisibility: Hashable, Codable, Sendable {
    case visible
    case hidden
}

public enum TopNavigationBarSection: Hashable, Codable, Sendable {
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

