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

/// Provides dynamic ids for iOS 18+ native zoom transitions.
///
/// Apple’s zoom transition API calls the destination controller’s `sourceViewProvider` closure both when pushing
/// and when popping. If the zoomed screen can change which “item” it represents without leaving the screen
/// (for example, paging between photos inside the detail view), the id you want to zoom back to can change too.
///
/// This protocol allows the SwiftUI hierarchy hosted by `NavigationShellHostingController` to update the
/// currently active ids, so the provider closure can read them from
/// `UIZoomTransitionSourceViewProviderContext.zoomedViewController`.
@MainActor
protocol _NavigationZoomDynamicIDsProviding: AnyObject {
    /// Optional override for the zoom source id used when *dismissing* a zoom transition.
    ///
    /// If `nil`, the library falls back to the id provided by `SUINavigationZoomTransition.sourceID`.
    var _suinavZoomDynamicSourceID: AnyHashable? { get set }

    /// Optional override for the zoom destination id used to resolve the destination hero rect.
    ///
    /// If `nil`, the library falls back to the id provided by `SUINavigationZoomTransition.destinationID`.
    var _suinavZoomDynamicDestinationID: AnyHashable? { get set }
}
