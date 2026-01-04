import Foundation

/// A high-level navigation transition request.
///
/// SUINavigationFusion uses a UIKit-backed `UINavigationController` stack under the hood.
/// Some transitions (such as iOS 18+ native zoom) are configured on the destination UIKit view controller.
///
/// - Important:
///   `SUINavigationTransition` is **not persisted** as part of navigation state restoration.
///   Restoration always rebuilds the stack without animations.
public enum SUINavigationTransition: Hashable {
    /// Uses the default system push/pop animation.
    case standard

    /// Uses the native iOS 18+ zoom transition when available and when a valid zoom source view exists.
    ///
    /// On iOS versions prior to 18, or when a source view cannot be resolved, the library falls back to `.standard`.
    case zoom(SUINavigationZoomTransition)
}

public extension SUINavigationTransition {
    /// Convenience for a zoom transition where the same identifier is used for both the source and destination.
    ///
    /// This is the common case for “thumbnail → detail” transitions:
    /// - mark the thumbnail with `.suinavZoomSource(id:)`
    /// - mark the hero image with `.suinavZoomDestination(id:)` (optional but recommended)
    static func zoom<ID: Hashable>(
        id: ID,
        interactiveDismiss: SUINavigationZoomTransition.InteractiveDismiss = .systemDefault
    ) -> Self {
        .zoom(.init(sourceID: AnyHashable(id), destinationID: AnyHashable(id), interactiveDismiss: interactiveDismiss))
    }

    /// Convenience for a zoom transition with separate source and destination identifiers.
    ///
    /// Use this when the source view and the destination “hero” view have different ids, or when you do not
    /// want to provide a destination id (in which case the system will choose a default alignment rect).
    static func zoom<SourceID: Hashable, DestinationID: Hashable>(
        sourceID: SourceID,
        destinationID: DestinationID? = nil,
        interactiveDismiss: SUINavigationZoomTransition.InteractiveDismiss = .systemDefault
    ) -> Self {
        .zoom(
            .init(
                sourceID: AnyHashable(sourceID),
                destinationID: destinationID.map(AnyHashable.init),
                interactiveDismiss: interactiveDismiss
            )
        )
    }
}

/// Configuration for a native iOS 18+ zoom transition.
///
/// The zoom transition needs a real UIKit `UIView` as a source for the animation.
/// In SUINavigationFusion, SwiftUI code provides these views by attaching:
/// - `.suinavZoomSource(id:)` on the source view
/// - `.suinavZoomDestination(id:)` on the destination hero view (optional)
///
/// The underlying UIKit system requests the source view both for pushing and popping.
/// Therefore the library stores **only ids** and resolves the actual views at transition time.
public struct SUINavigationZoomTransition: Hashable {
    /// Policy for whether the system’s interactive zoom-dismiss gesture should be allowed.
    ///
    /// Zoom transitions can add additional interactive gestures (in addition to edge-swipe back).
    /// Use `.disabled` to prevent them (useful for “no interactive back” flows).
    public enum InteractiveDismiss: Hashable, Sendable {
        /// Uses UIKit’s system default.
        case systemDefault
        /// Disables interactive zoom-dismiss gestures for this transition.
        case disabled
    }

    /// Identifier of the view marked with `.suinavZoomSource(id:)` in the source screen.
    public var sourceID: AnyHashable
    /// Optional identifier of the view marked with `.suinavZoomDestination(id:)` in the destination screen.
    ///
    /// When provided, the library can use it to improve alignment (zoom into the hero rect instead of the whole screen).
    public var destinationID: AnyHashable?
    /// Controls whether interactive zoom-dismiss gestures are allowed.
    public var interactiveDismiss: InteractiveDismiss

    public init(
        sourceID: AnyHashable,
        destinationID: AnyHashable? = nil,
        interactiveDismiss: InteractiveDismiss = .systemDefault
    ) {
        self.sourceID = sourceID
        self.destinationID = destinationID
        self.interactiveDismiss = interactiveDismiss
    }
}
