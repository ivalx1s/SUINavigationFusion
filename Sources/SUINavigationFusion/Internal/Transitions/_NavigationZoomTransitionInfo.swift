import Foundation
#if canImport(UIKit)
import UIKit
#endif

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

#if canImport(UIKit)
/// Stores transition-scoped “frozen” zoom ids.
///
/// UIKit may call the zoom source-view provider multiple times during a single transition (especially for
/// interactive dismiss + completion). If the effective ids change between calls (because SwiftUI updates
/// `.suinavZoomDismissTo(...)` while the transition is in flight), UIKit can enter undefined behavior
/// (including repeated/looping transitions).
///
/// To make the system robust, SUINavigationFusion freezes the effective ids for the duration of a transition.
@MainActor
protocol _NavigationZoomFrozenIDsProviding: AnyObject {
    var _suinavZoomFrozenSourceID: AnyHashable? { get set }
    var _suinavZoomFrozenDestinationID: AnyHashable? { get set }
}

/// Stores transition lifecycle state for a zoomed controller.
///
/// Used to defer `.suinavZoomDismissTo(...)` updates while UIKit is mid-transition.
@MainActor
protocol _NavigationZoomTransitionStateProviding: AnyObject {
    /// `true` while a zoom transition is in flight (push, pop, interactive dismiss + completion/cancel).
    var _suinavZoomTransitionIsInFlight: Bool { get set }

    /// The latest dynamic id updates observed during the transition.
    ///
    /// These are applied once UIKit reports that the transition finished/canceled.
    var _suinavZoomPendingDynamicSourceID: AnyHashable? { get set }
    var _suinavZoomPendingDynamicDestinationID: AnyHashable? { get set }

    /// Diagnostic counter: how many times UIKit requested the zoom source view during the current transition.
    var _suinavZoomSourceProviderCallCount: Int { get set }
}

@MainActor
protocol _NavigationZoomLastSourceViewProviding: AnyObject {
    /// The last source view successfully resolved by the zoom provider during the current transition.
    ///
    /// Used as a fallback if the registry cannot resolve the view on a subsequent provider call.
    var _suinavZoomLastSourceView: UIView? { get set }

    /// Identity of the source view controller that `_suinavZoomLastSourceView` belongs to.
    ///
    /// Prevents reusing a cached view across different source view controllers.
    var _suinavZoomLastSourceViewControllerID: ObjectIdentifier? { get set }

    /// The zoom source id that `_suinavZoomLastSourceView` corresponds to.
    ///
    /// Prevents reusing a cached view across different ids if the provider is called multiple times.
    var _suinavZoomLastSourceID: AnyHashable? { get set }
}

@MainActor
func _suinavResolveFrozenZoomIDs(
    zoomedViewController: UIViewController,
    staticSourceID: AnyHashable,
    staticDestinationID: AnyHashable?
) -> (sourceID: AnyHashable, destinationID: AnyHashable?) {
    if
        let frozen = zoomedViewController as? _NavigationZoomFrozenIDsProviding,
        let sourceID = frozen._suinavZoomFrozenSourceID
    {
        return (sourceID, frozen._suinavZoomFrozenDestinationID)
    }

    var sourceID = staticSourceID
    var destinationID = staticDestinationID

    if let dynamic = zoomedViewController as? _NavigationZoomDynamicIDsProviding {
        sourceID = dynamic._suinavZoomDynamicSourceID ?? sourceID
        destinationID = dynamic._suinavZoomDynamicDestinationID ?? destinationID
    }

    if let frozen = zoomedViewController as? _NavigationZoomFrozenIDsProviding {
        frozen._suinavZoomFrozenSourceID = sourceID
        frozen._suinavZoomFrozenDestinationID = destinationID
    }

    return (sourceID, destinationID)
}

@MainActor
func _suinavClearFrozenZoomIDs(on viewController: UIViewController) {
    guard let frozen = viewController as? _NavigationZoomFrozenIDsProviding else { return }
    frozen._suinavZoomFrozenSourceID = nil
    frozen._suinavZoomFrozenDestinationID = nil
}

@MainActor
func _suinavApplyPendingZoomDynamicIDsIfNeeded(on viewController: UIViewController) {
    guard
        let state = viewController as? _NavigationZoomTransitionStateProviding,
        let dynamic = viewController as? _NavigationZoomDynamicIDsProviding
    else {
        return
    }

    if let pending = state._suinavZoomPendingDynamicSourceID {
        dynamic._suinavZoomDynamicSourceID = pending
        state._suinavZoomPendingDynamicSourceID = nil
    }
    if let pending = state._suinavZoomPendingDynamicDestinationID {
        dynamic._suinavZoomDynamicDestinationID = pending
        state._suinavZoomPendingDynamicDestinationID = nil
    }
}

@MainActor
func _suinavClearLastResolvedZoomSourceView(on viewController: UIViewController) {
    guard let provider = viewController as? _NavigationZoomLastSourceViewProviding else { return }
    provider._suinavZoomLastSourceView = nil
    provider._suinavZoomLastSourceViewControllerID = nil
    provider._suinavZoomLastSourceID = nil
}
#endif
