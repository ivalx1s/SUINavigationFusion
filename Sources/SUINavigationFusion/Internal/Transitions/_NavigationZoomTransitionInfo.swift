import Foundation

/// Ephemeral metadata attached to pushed hosting controllers when using iOS 18+ native zoom transitions.
///
/// UIKit zoom transitions are configured via `UIViewController.preferredTransition` on the *destination*
/// controller. The transition coordinator does not expose the original `SUINavigationTransition` value,
/// so we attach the relevant ids to the hosting controller at push time.
///
/// The coordinator then uses this metadata to:
/// - temporarily hide the source/destination anchor views during the transition (prevents cross-fade artifacts),
/// - resolve the correct anchor views for the current transition direction.
///
/// - Note:
///   This is **not persisted** and has no effect on state restoration.
struct _NavigationZoomTransitionInfo: Hashable {
    /// Anchor id registered by `.suinavZoomSource(id:)`.
    let sourceID: AnyHashable

    /// Optional anchor id registered by `.suinavZoomDestination(id:)`.
    let destinationID: AnyHashable?
}

@MainActor
protocol _NavigationZoomTransitionInfoProviding: AnyObject {
    var _suinavZoomTransitionInfo: _NavigationZoomTransitionInfo? { get set }
}
