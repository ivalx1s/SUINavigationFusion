import SwiftUI

public extension View {
    /// Updates which zoom source/destination ids UIKit should use when dismissing an iOS 18+ zoom transition.
    ///
    /// Apple’s zoom transition API (`preferredTransition = .zoom { context in ... }`) calls the destination
    /// controller’s source-view provider both when pushing and when popping. If your zoomed screen can change
    /// which “item” it represents without leaving the screen (for example, paging between photos inside a
    /// single detail view controller), the correct thumbnail to zoom back to can change over time.
    ///
    /// Apply this modifier on the *zoomed* (detail) screen and update `id` whenever the currently displayed
    /// item changes. Internally, the library stores the value on the underlying hosting controller so the
    /// zoom transition can read it from `UIZoomTransitionSourceViewProviderContext.zoomedViewController`.
    ///
    /// - Important:
    ///   The `id` must match a source view registered in the *source* screen with `.suinavZoomSource(id:)`
    ///   at the time of dismiss. If the source view can't be resolved (for example, the cell is off-screen),
    ///   UIKit may fall back to a degraded animation.
    ///
    /// - Note:
    ///   This modifier sets both the *source id* (what to zoom back to) and the *destination id* (the hero rect
    ///   inside the zoomed screen) to the same value, which matches the common “thumbnail id == hero id” setup.
    func suinavZoomDismissTo<ID: Hashable>(id: ID) -> some View {
        #if canImport(UIKit)
        return background(_SUINavigationZoomDismissIDsRegistrar(sourceID: AnyHashable(id), destinationID: AnyHashable(id)))
        #else
        return self
        #endif
    }

    /// Updates which zoom source/destination ids UIKit should use when dismissing an iOS 18+ zoom transition.
    ///
    /// Use this overload when the destination “hero” view id differs from the source id (or when you do not
    /// want to override the destination id).
    ///
    /// - Parameters:
    ///   - sourceID: The id to zoom back to on dismiss. Must match `.suinavZoomSource(id:)` in the source screen.
    ///   - destinationID: Optional id of the destination hero element. If provided, the library will use it for:
    ///     - alignment rect lookups (when `alignmentRectPolicy` uses destination anchor), and
    ///     - interactive dismiss policy evaluation that needs the destination anchor frame.
    func suinavZoomDismissTo<SourceID: Hashable, DestinationID: Hashable>(
        sourceID: SourceID,
        destinationID: DestinationID?
    ) -> some View {
        #if canImport(UIKit)
        return background(
            _SUINavigationZoomDismissIDsRegistrar(
                sourceID: AnyHashable(sourceID),
                destinationID: destinationID.map { AnyHashable($0) }
            )
        )
        #else
        return self
        #endif
    }
}

#if canImport(UIKit)
import UIKit

/// SwiftUI → UIKit bridge that writes dynamic zoom ids into the hosting controller.
///
/// We don't rely on PreferenceKeys here because this is fundamentally UIKit state: the value must be readable
/// synchronously from `UIZoomTransitionSourceViewProviderContext.zoomedViewController` while UIKit is running
/// the transition.
private struct _SUINavigationZoomDismissIDsRegistrar: UIViewRepresentable {
    let sourceID: AnyHashable?
    let destinationID: AnyHashable?

    func makeCoordinator() -> Coordinator {
        Coordinator(sourceID: sourceID, destinationID: destinationID)
    }

    func makeUIView(context: Context) -> _CaptureView {
        let view = _CaptureView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: _CaptureView, context: Context) {
        context.coordinator.sourceID = sourceID
        context.coordinator.destinationID = destinationID

        uiView.onUpdate = { [weak coordinator = context.coordinator] view in
            Task { @MainActor in
                coordinator?.applyIfPossible(from: view)
            }
        }

        // SwiftUI may attach the view to a superview after `updateUIView` completes.
        // Register on the next run loop tick to reduce flakiness.
        Task { @MainActor in
            await Task.yield()
            context.coordinator.applyIfPossible(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: _CaptureView, coordinator: Coordinator) {
        uiView.onUpdate = nil
        Task { @MainActor in
            coordinator.clearIfNeeded()
        }
    }

    @MainActor
    final class Coordinator {
        var sourceID: AnyHashable?
        var destinationID: AnyHashable?

        private weak var lastHost: (_NavigationZoomDynamicIDsProviding & UIViewController)?

        init(sourceID: AnyHashable?, destinationID: AnyHashable?) {
            self.sourceID = sourceID
            self.destinationID = destinationID
        }

        func applyIfPossible(from view: UIView) {
            guard let host = findHostingController(from: view) else { return }
            lastHost = host

            // If a zoom transition is currently in flight, do not mutate the live dynamic ids.
            // UIKit may query the source view provider multiple times during interactive dismiss + completion;
            // if ids change mid-flight, UIKit can enter undefined behavior. Defer the latest requested ids and
            // apply them once the transition finishes.
            if let state = host as? _NavigationZoomTransitionStateProviding, state._suinavZoomTransitionIsInFlight {
                if let sourceID {
                    state._suinavZoomPendingDynamicSourceID = sourceID
                }
                if let destinationID {
                    state._suinavZoomPendingDynamicDestinationID = destinationID
                }
                return
            }

            if let sourceID {
                host._suinavZoomDynamicSourceID = sourceID
            }
            if let destinationID {
                host._suinavZoomDynamicDestinationID = destinationID
            }
        }

        func clearIfNeeded() {
            guard let host = lastHost else { return }
            if let state = host as? _NavigationZoomTransitionStateProviding {
                state._suinavZoomPendingDynamicSourceID = nil
                state._suinavZoomPendingDynamicDestinationID = nil
                state._suinavZoomTransitionIsInFlight = false
            }
            host._suinavZoomDynamicSourceID = nil
            host._suinavZoomDynamicDestinationID = nil
            lastHost = nil
        }

        private func findHostingController(from view: UIView) -> (_NavigationZoomDynamicIDsProviding & UIViewController)? {
            var responder: UIResponder? = view
            while let next = responder?.next {
                if let host = next as? (UIViewController & _NavigationZoomDynamicIDsProviding) {
                    return host
                }
                responder = next
            }
            return nil
        }
    }

    /// A view that notifies when SwiftUI attaches/relayouts it.
    final class _CaptureView: UIView {
        var onUpdate: ((UIView) -> Void)?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            onUpdate?(self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onUpdate?(self)
        }
    }
}
#endif
