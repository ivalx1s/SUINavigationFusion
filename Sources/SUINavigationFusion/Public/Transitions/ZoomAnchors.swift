import SwiftUI

public extension View {
    /// Marks this view as a **zoom source** for an iOS 18+ native zoom transition.
    ///
    /// Attach this to the visual element that should zoom into the next screen (e.g. a thumbnail image).
    /// The identifier must match the `NavigationZoomTransition.sourceID` you use when pushing.
    ///
    /// Example:
    /// ```swift
    /// Thumbnail(photo: photo)
    ///   .suinavZoomSource(id: photo.id)
    /// ```
    ///
    /// - Important:
    ///   If multiple views register the same `id` at the same time, the “last writer wins”.
    ///   Prefer ids that are unique among currently visible source views.
    func suinavZoomSource<ID: Hashable>(id: ID) -> some View {
        #if canImport(UIKit)
        return background(_SUINavigationZoomAnchorRegistrar(id: AnyHashable(id), kind: .source))
        #else
        return self
        #endif
    }

    /// Marks this view as a **zoom destination** (alignment rect) for an iOS 18+ native zoom transition.
    ///
    /// Attach this to the “hero” element on the destination screen (e.g. a large image). When provided,
    /// the library can align the zoom animation to this rect instead of zooming into the full screen.
    ///
    /// Example:
    /// ```swift
    /// Image(uiImage: photo.image)
    ///   .resizable()
    ///   .scaledToFit()
    ///   .suinavZoomDestination(id: photo.id)
    /// ```
    ///
    /// - Important:
    ///   Destination anchors are optional, but they often improve visual quality for complex detail screens.
    func suinavZoomDestination<ID: Hashable>(id: ID) -> some View {
        #if canImport(UIKit)
        return background(_SUINavigationZoomAnchorRegistrar(id: AnyHashable(id), kind: .destination))
        #else
        return self
        #endif
    }
}

#if canImport(UIKit)
import UIKit

private enum _SUINavigationZoomAnchorKind {
    case source
    case destination
}

/// A tiny SwiftUI → UIKit bridge that captures the backing `UIView` for a SwiftUI subtree.
///
/// UIKit zoom transitions require concrete `UIView` instances. SwiftUI does not expose them directly,
/// so we insert an invisible `UIView` into the hierarchy and register its container view.
private struct _SUINavigationZoomAnchorRegistrar: UIViewRepresentable {
    let id: AnyHashable
    let kind: _SUINavigationZoomAnchorKind

    @EnvironmentObject private var navigator: Navigator

    func makeCoordinator() -> Coordinator {
        Coordinator(id: id, kind: kind)
    }

    func makeUIView(context: Context) -> _CaptureView {
        let view = _CaptureView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: _CaptureView, context: Context) {
        Task { @MainActor in
            context.coordinator.navigator = navigator
        }
        uiView.onUpdate = { [weak coordinator = context.coordinator] view in
            Task { @MainActor in
                coordinator?.registerIfPossible(anchorView: view)
            }
        }

        // SwiftUI may attach the view to a superview after `updateUIView` completes.
        // Register on the next run loop tick to reduce flakiness.
        Task { @MainActor in
            await Task.yield()
            context.coordinator.registerIfPossible(anchorView: uiView)
        }
    }

    static func dismantleUIView(_ uiView: _CaptureView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.unregisterIfNeeded()
        }
        uiView.onUpdate = nil
    }

    @MainActor
    final class Coordinator {
        let id: AnyHashable
        let kind: _SUINavigationZoomAnchorKind
        weak var navigator: Navigator?
        weak var lastRegisteredView: UIView?

        init(id: AnyHashable, kind: _SUINavigationZoomAnchorKind) {
            self.id = id
            self.kind = kind
        }

        /// Resolves the UIKit view we should register as a zoom anchor for this SwiftUI subtree.
        ///
        /// SwiftUI often inserts `UIViewRepresentable` content into intermediate hosting containers that do **not**
        /// include the “real” rendered content of the view you're modifying.
        ///
        /// For example, when using `.background(...)`, SwiftUI may create a container that hosts only the background
        /// view (our capture view), while the actual content lives in a sibling container.
        ///
        /// UIKit's zoom transition needs a view whose snapshot represents the visible hero element, and we also hide
        /// that same view during the transition to avoid seeing both:
        /// - the static original thumbnail, and
        /// - the animated zoom snapshot.
        ///
        /// Therefore we walk up the superview chain and pick the first ancestor that:
        /// - is sized like the capture view (when possible), and
        /// - appears to be a composite container (has more than one subview).
        ///
        /// This is a best-effort heuristic; it keeps the API SwiftUI-friendly without requiring an introspection
        /// dependency, while producing UIKit views that behave like SwiftUI's `matchedTransitionSource`.
        private func resolveAnchorContainerView(for captureView: UIView) -> UIView {
            let referenceSize = captureView.bounds.size

            var bestCandidate: UIView?
            var current: UIView? = captureView

            // Keep the search bounded — SwiftUI view trees can be deep.
            for _ in 0..<12 {
                guard let parent = current?.superview else { break }

                // We want a container that includes more than just our capture view.
                // The first composite container is a good fallback.
                if bestCandidate == nil, parent.subviews.count > 1, parent.bounds.size != .zero {
                    bestCandidate = parent
                }

                // Prefer a composite container that matches the capture view's size.
                if
                    parent.subviews.count > 1,
                    referenceSize != .zero,
                    parent.bounds.size == referenceSize
                {
                    return parent
                }

                current = parent
            }

            return bestCandidate ?? captureView.superview ?? captureView
        }

        func registerIfPossible(anchorView: UIView) {
            guard let navigator else { return }

            // We want to register a view whose snapshot actually represents the SwiftUI subtree
            // (and which we can safely hide during the transition to avoid duplicate heroes).
            let target = resolveAnchorContainerView(for: anchorView)
            lastRegisteredView = target

            switch kind {
            case .source:
                navigator._zoomViewRegistry.setSourceView(target, for: id)
            case .destination:
                navigator._zoomViewRegistry.setDestinationView(target, for: id)
            }
        }

        func unregisterIfNeeded() {
            guard let navigator else { return }
            let target = lastRegisteredView
            switch kind {
            case .source:
                navigator._zoomViewRegistry.clearSourceView(for: id, ifCurrentViewIs: target)
            case .destination:
                navigator._zoomViewRegistry.clearDestinationView(for: id, ifCurrentViewIs: target)
            }
            lastRegisteredView = nil
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
