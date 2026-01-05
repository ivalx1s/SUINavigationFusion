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
        // UIKit’s zoom transition requires a `UIView` to animate from.
        //
        // SwiftUI doesn’t expose the backing UIKit view for a `View`, so we insert a dedicated capture view that:
        // - is registered as the zoom source (`Navigator._zoomViewRegistry`)
        // - can display a snapshot of the *real* SwiftUI content during the transition
        //
        // The actual snapshot is captured right before the transition starts (see `Navigator._applyTransitionIfNeeded`).
        return modifier(_SUINavigationZoomSourceModifier(id: id))
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

/// A modifier that installs a zoom capture view and hides the original content while zooming.
///
/// The goal is to mimic SwiftUI’s `matchedTransitionSource` behavior:
/// - the source view is visually removed during the transition
/// - UIKit animates a snapshot in its place
///
/// We can't reliably find “the real UIKit view” for a SwiftUI subtree, so the library instead:
/// 1) overlays a dedicated `_SUINavigationZoomCaptureView`
/// 2) captures a snapshot of the underlying screen and places it into that capture view
/// 3) hides the original SwiftUI content by setting opacity to 0 while the transition is active
///
/// This design trades some overhead (one snapshot per zoom transition) for correctness and predictable behavior.
private struct _SUINavigationZoomSourceModifier<ID: Hashable>: ViewModifier {
    let id: ID
    @EnvironmentObject private var navigator: Navigator

    func body(content: Content) -> some View {
        let isZooming = navigator._activeZoomSourceID == AnyHashable(id)

        return content
            // Hide the real content during the transition so it doesn't stay behind the moving snapshot.
            .opacity(isZooming ? 0 : 1)
            // Keep the capture view in the hierarchy so UIKit can snapshot it.
            // The view is transparent when no snapshot is installed.
            .overlay(
                _SUINavigationZoomAnchorRegistrar(id: AnyHashable(id), kind: .source)
                    .allowsHitTesting(false)
            )
    }
}

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

    func makeUIView(context: Context) -> _SUINavigationZoomCaptureView {
        let view = _SUINavigationZoomCaptureView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: _SUINavigationZoomCaptureView, context: Context) {
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

    static func dismantleUIView(_ uiView: _SUINavigationZoomCaptureView, coordinator: Coordinator) {
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

            // Register the capture view itself.
            //
            // For `.source`, UIKit will animate (snapshot) this view, so it needs to be:
            // - sized like the SwiftUI subtree
            // - able to display a snapshot image
            //
            // For `.destination`, we use the capture view primarily for geometry (alignment rect).
            let target = anchorView
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

}

/// A UIKit view used as a zoom source/destination anchor.
///
/// For zoom transitions, the library installs a snapshot image into this view so UIKit has visible content to animate.
final class _SUINavigationZoomCaptureView: UIView {
    var onUpdate: ((UIView) -> Void)?

    private let snapshotImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(snapshotImageView)
        snapshotImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            snapshotImageView.topAnchor.constraint(equalTo: topAnchor),
            snapshotImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            snapshotImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            snapshotImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        onUpdate?(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onUpdate?(self)
    }

    /// Sets the snapshot that UIKit should animate for the next zoom transition.
    ///
    /// If `nil`, the view becomes visually empty (transparent).
    func setSnapshotImage(_ image: UIImage?) {
        snapshotImageView.image = image
    }
}
#endif
