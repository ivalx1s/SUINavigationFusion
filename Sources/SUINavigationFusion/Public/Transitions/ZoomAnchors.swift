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
            .overlay(
                _SUINavigationZoomAnchorRegistrar(id: AnyHashable(id), kind: .source)
                    .allowsHitTesting(false)
                // Note: do not gate this overlay’s visibility with SwiftUI `.opacity`.
                //
                // UIKit asks for the source view synchronously when starting a zoom transition. SwiftUI’s view
                // update (driven by `_activeZoomSourceID`) can land on the next run loop tick, which can cause
                // the capture view to be snapshotted while still visually transparent (“invisible lift-off”).
                //
                // Instead, we control the backing `UIView`’s alpha in `updateUIView`, and additionally force
                // it visible in `Navigator._applyTransitionIfNeeded` right before returning it to UIKit.
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
@MainActor
private struct _SUINavigationZoomAnchorRegistrar: UIViewRepresentable {
    let id: AnyHashable
    let kind: _SUINavigationZoomAnchorKind

    @EnvironmentObject private var navigator: Navigator

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> _SUINavigationZoomCaptureView {
        let view = _SUINavigationZoomCaptureView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: _SUINavigationZoomCaptureView, context: Context) {
        context.coordinator.update(id: id, kind: kind, navigator: navigator)

        uiView.onUpdate = { [weak coordinator = context.coordinator] view in
            Task { @MainActor in
                coordinator?.registerIfPossible(anchorView: view)
            }
        }

        // Keep the capture view visually hidden outside of a transition.
        //
        // The capture view is a temporary snapshot container for UIKit’s zoom transition. If it remains visible
        // after a pop, it can “freeze” the cell by covering the real SwiftUI content with the last snapshot.
        //
        // We derive visibility from `_activeZoomSourceID` (set just-in-time in the zoom source provider).
        // This is intentionally done at the UIKit view level to avoid SwiftUI update timing races.
        if kind == .source {
            uiView.alpha = (navigator._activeZoomSourceID == id) ? 1 : 0
        }

        // Register immediately when possible. This reduces flakiness for transitions that start soon after
        // the SwiftUI update (e.g. a tap on a freshly-rendered grid cell).
        if uiView.window != nil {
            context.coordinator.registerIfPossible(anchorView: uiView)
        }
    }

    static func dismantleUIView(_ uiView: _SUINavigationZoomCaptureView, coordinator: Coordinator) {
        uiView.onUpdate = nil
        coordinator.unregisterIfNeeded()
    }

    @MainActor
    final class Coordinator {
        private var id: AnyHashable?
        private var kind: _SUINavigationZoomAnchorKind?
        weak var navigator: Navigator?
        weak var lastRegisteredView: UIView?

        func update(id: AnyHashable, kind: _SUINavigationZoomAnchorKind, navigator: Navigator) {
            // SwiftUI can reuse backing UIViews in lazy containers (List/LazyVGrid).
            // If the id changes, we must unregister the previous mapping, otherwise future transitions can resolve
            // to a stale view and snapshot the wrong on-screen element.
            if self.id != id || self.kind != kind || self.navigator !== navigator {
                unregisterIfNeeded()
            }
            self.id = id
            self.kind = kind
            self.navigator = navigator
        }

        func registerIfPossible(anchorView: UIView) {
            guard let navigator, let id, let kind else { return }

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
            guard let navigator, let id, let kind else { return }
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
