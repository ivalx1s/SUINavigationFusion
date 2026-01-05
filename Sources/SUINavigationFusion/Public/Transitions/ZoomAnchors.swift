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

        func registerIfPossible(anchorView: UIView) {
            guard let navigator else { return }

            // We want to register a view that has the “real” size of the SwiftUI subtree.
            // In practice, the capture view itself is tiny/empty, while its superview is the container.
            let target = anchorView.superview ?? anchorView
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
