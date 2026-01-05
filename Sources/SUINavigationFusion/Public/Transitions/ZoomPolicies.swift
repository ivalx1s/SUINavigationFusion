import CoreGraphics
import SwiftUI

// MARK: - Interactive dismiss

/// Context passed to `SUINavigationZoomInteractiveDismissPolicy` when deciding whether a zoom interactive dismiss
/// should begin.
///
/// UIKit calls the underlying hook (`UIZoomTransitionOptions.interactiveDismissShouldBegin`) right before starting an
/// interactive dismissal (e.g. swipe-down/pinch-to-dismiss in a Photos-style detail view).
///
/// SUINavigationFusion wraps UIKit’s context to:
/// - avoid leaking UIKit types into public API
/// - provide additional derived information (like `destinationAnchorFrame`)
public struct SUINavigationZoomInteractiveDismissContext {
    /// Whether UIKit would begin the interaction under the current conditions by default.
    ///
    /// If you want a policy that “adds constraints on top of UIKit”, use this as a baseline.
    public let systemWillBegin: Bool

    /// Location of the interaction in the *displayed (zoomed) view controller’s* coordinate space.
    public let location: CGPoint

    /// The gesture’s velocity.
    public let velocity: CGVector

    /// Frame of the destination anchor (the view marked with `.suinavZoomDestination(id:)`) in the displayed
    /// view controller’s coordinate space.
    ///
    /// `nil` when:
    /// - the zoom transition has no `destinationID`, or
    /// - the destination anchor view cannot be resolved.
    public let destinationAnchorFrame: CGRect?

    /// Convenience for the common “only allow dismiss if gesture starts from the hero” rule.
    public var isInDestinationAnchor: Bool {
        destinationAnchorFrame?.contains(location) == true
    }

    public init(
        systemWillBegin: Bool,
        location: CGPoint,
        velocity: CGVector,
        destinationAnchorFrame: CGRect?
    ) {
        self.systemWillBegin = systemWillBegin
        self.location = location
        self.velocity = velocity
        self.destinationAnchorFrame = destinationAnchorFrame
    }
}

/// Policy controlling whether iOS 18+ zoom interactive dismiss gestures are allowed to begin.
///
/// UIKit’s zoom transitions add additional interactive gestures (e.g. swipe-down/pinch) that are separate from
/// the standard edge-swipe back gesture. This policy lets you:
/// - disable them entirely for a specific transition
/// - gate them behind common rules (e.g. “start inside the hero”, “downward swipe only”)
/// - provide a fully custom decision closure
///
/// - Important:
///   If you push a screen with `disableBackGesture: true`, SUINavigationFusion **also disables** zoom interactive
///   dismiss gestures for that push, regardless of this policy. This keeps the library’s “no interactive back”
///   contract consistent across both edge-swipe back and zoom dismiss.
public struct SUINavigationZoomInteractiveDismissPolicy {
    /// Custom decision closure.
    ///
    /// - Important:
    ///   Called from UIKit’s transition machinery. UIKit expects a synchronous decision.
    ///
    /// The closure is executed on the main thread.
    public typealias Handler = (SUINavigationZoomInteractiveDismissContext) -> Bool

    @usableFromInline
    enum _Implementation {
        case systemDefault
        case custom(Handler)
    }

    @usableFromInline
    let _implementation: _Implementation

    private init(_ implementation: _Implementation) {
        self._implementation = implementation
    }

    /// Uses UIKit’s default decision (the library leaves the underlying UIKit hook unset).
    public nonisolated(unsafe) static let systemDefault = Self(.systemDefault)

    /// Disables zoom interactive dismiss gestures.
    public nonisolated(unsafe) static let disabled = Self.custom { _ in false }

    /// Fully custom decision.
    public static func custom(_ handler: @escaping Handler) -> Self {
        Self(.custom(handler))
    }

    /// Allows interactive dismiss only when the gesture begins inside the destination anchor’s frame.
    ///
    /// This is useful for “Photos-like” UIs where you want dismiss to begin only when the user interacts with
    /// the hero element, not any scrollable content around it.
    ///
    /// - Parameter fallback: Used when `destinationAnchorFrame` cannot be resolved.
    public static func onlyFromDestinationAnchor(
        fallback: Self = .systemDefault
    ) -> Self {
        .custom { context in
            guard context.systemWillBegin else { return false }
            guard context.destinationAnchorFrame != nil else { return fallback._evaluate(context) }
            return context.isInDestinationAnchor
        }
    }

    /// Allows interactive dismiss only for predominantly downward swipes.
    ///
    /// - Parameters:
    ///   - minimumVelocityY: Minimum downward velocity (`dy`) required.
    ///   - minimumVerticalRatio: How much larger `|dy|` must be than `|dx|` (e.g. `1.2` means 20% more vertical).
    public static func downwardSwipe(
        minimumVelocityY: CGFloat = 0,
        minimumVerticalRatio: CGFloat = 1.2
    ) -> Self {
        .custom { context in
            guard context.systemWillBegin else { return false }
            let dx = context.velocity.dx
            let dy = context.velocity.dy
            guard dy >= minimumVelocityY else { return false }
            guard abs(dy) >= abs(dx) * minimumVerticalRatio else { return false }
            return true
        }
    }

    /// Gates interactive dismiss behind an external condition (e.g. “scroll is at top”).
    ///
    /// This is a common pattern for detail screens that contain a scroll view:
    /// only allow dismiss when the scroll view is scrolled to the top.
    ///
    /// - Parameters:
    ///   - isEnabled: External condition queried at interaction time.
    ///   - fallback: Policy used when `isEnabled()` returns `false`.
    public static func when(
        _ isEnabled: @escaping () -> Bool,
        otherwise fallback: Self = .disabled
    ) -> Self {
        .custom { context in
            if isEnabled() {
                // Keep UIKit as a baseline unless the caller explicitly overrides it via `.custom`.
                return context.systemWillBegin
            }
            return fallback._evaluate(context)
        }
    }

    /// Combines two policies with logical AND.
    ///
    /// This is useful to build “preset + app-specific rule” compositions:
    ///
    /// ```swift
    /// .onlyFromDestinationAnchor().and(.downwardSwipe(minimumVelocityY: 200))
    /// ```
    public func and(_ other: Self) -> Self {
        .custom { context in
            self._evaluate(context) && other._evaluate(context)
        }
    }

    /// Combines two policies with logical OR.
    public func or(_ other: Self) -> Self {
        .custom { context in
            self._evaluate(context) || other._evaluate(context)
        }
    }

    @usableFromInline
    func _evaluate(_ context: SUINavigationZoomInteractiveDismissContext) -> Bool {
        switch _implementation {
        case .systemDefault:
            return context.systemWillBegin
        case .custom(let handler):
            return handler(context)
        }
    }

    @usableFromInline
    var _isPureSystemDefault: Bool {
        if case .systemDefault = _implementation { return true }
        return false
    }
}

// MARK: - Alignment rect

/// Context passed to `SUINavigationZoomAlignmentRectPolicy` when choosing an alignment rect for a zoom transition.
///
/// UIKit uses the alignment rect to decide *which area of the destination screen* the source view should align to.
/// This can dramatically improve the visual quality for complex detail screens (reducing “ghosting” and jumps).
public struct SUINavigationZoomAlignmentRectContext {
    /// Bounds of the zoomed view controller’s root view.
    public let zoomedViewBounds: CGRect

    /// Safe-area bounds of the zoomed view controller’s root view.
    public let zoomedSafeAreaBounds: CGRect

    /// Size of the source view used for the zoom transition.
    public let sourceViewSize: CGSize

    /// Frame of the destination anchor (the view marked with `.suinavZoomDestination(id:)`) in the zoomed view
    /// controller’s coordinate space.
    ///
    /// `nil` when the destination anchor view cannot be resolved.
    public let destinationAnchorFrame: CGRect?

    public init(
        zoomedViewBounds: CGRect,
        zoomedSafeAreaBounds: CGRect,
        sourceViewSize: CGSize,
        destinationAnchorFrame: CGRect?
    ) {
        self.zoomedViewBounds = zoomedViewBounds
        self.zoomedSafeAreaBounds = zoomedSafeAreaBounds
        self.sourceViewSize = sourceViewSize
        self.destinationAnchorFrame = destinationAnchorFrame
    }
}

/// Policy controlling the zoom transition alignment rect (iOS 18+).
///
/// In UIKit terms, this maps to `UIZoomTransitionOptions.alignmentRectProvider`.
/// The returned rect must be in the zoomed view controller’s root view coordinate space.
///
/// Returning `nil` indicates “no preference” (UIKit will choose a default).
public struct SUINavigationZoomAlignmentRectPolicy {
    /// Custom alignment-rect provider.
    ///
    /// - Important:
    ///   Called from UIKit’s transition machinery. UIKit expects a synchronous decision.
    ///
    /// The closure is executed on the main thread.
    public typealias Handler = (SUINavigationZoomAlignmentRectContext) -> CGRect?

    /// Fallback strategy used when a destination anchor cannot be resolved.
    public enum Fallback: Hashable, Sendable {
        /// Return `nil` (“no preference” / UIKit default).
        case systemDefault
        /// Use `zoomedViewBounds`.
        case zoomedViewBounds
        /// Use `zoomedSafeAreaBounds`.
        case zoomedSafeAreaBounds
    }

    @usableFromInline
    enum _Implementation {
        case systemDefault
        case custom(Handler)
    }

    @usableFromInline
    let _implementation: _Implementation

    private init(_ implementation: _Implementation) {
        self._implementation = implementation
    }

    /// Uses UIKit’s default alignment (the library leaves the underlying UIKit hook unset).
    public nonisolated(unsafe) static let systemDefault = Self(.systemDefault)

    /// Fully custom alignment-rect provider.
    public static func custom(_ handler: @escaping Handler) -> Self {
        Self(.custom(handler))
    }

    /// Aligns the zoom transition to the destination anchor rect (the view marked with `.suinavZoomDestination(id:)`).
    ///
    /// - Parameter fallback: Used when the destination anchor cannot be resolved.
    public static func destinationAnchor(
        fallback: Fallback = .zoomedViewBounds
    ) -> Self {
        .custom { context in
            if let rect = context.destinationAnchorFrame {
                return rect
            }
            return fallback._resolve(in: context)
        }
    }

    /// Aligns to the destination anchor rect with insets applied (in the zoomed view controller’s coordinate space).
    public static func destinationAnchor(
        inset: EdgeInsets,
        fallback: Fallback = .zoomedViewBounds
    ) -> Self {
        .custom { context in
            if let rect = context.destinationAnchorFrame {
                return rect._inset(by: inset)
            }
            return fallback._resolve(in: context)
        }
    }

    /// Aligns to an aspect-fit rect inside the destination anchor that matches the source view’s aspect ratio.
    ///
    /// This can improve results when the destination anchor is a container larger than the visual content.
    public static func destinationAnchorAspectFitToSource(
        fallback: Fallback = .zoomedViewBounds
    ) -> Self {
        .custom { context in
            guard let rect = context.destinationAnchorFrame else {
                return fallback._resolve(in: context)
            }
            return CGRect._aspectFit(inside: rect, sourceSize: context.sourceViewSize) ?? rect
        }
    }

    @usableFromInline
    func _evaluate(_ context: SUINavigationZoomAlignmentRectContext) -> CGRect? {
        switch _implementation {
        case .systemDefault:
            return nil
        case .custom(let handler):
            return handler(context)
        }
    }

    @usableFromInline
    var _isPureSystemDefault: Bool {
        if case .systemDefault = _implementation { return true }
        return false
    }
}

private extension SUINavigationZoomAlignmentRectPolicy.Fallback {
    func _resolve(in context: SUINavigationZoomAlignmentRectContext) -> CGRect? {
        switch self {
        case .systemDefault:
            return nil
        case .zoomedViewBounds:
            return context.zoomedViewBounds
        case .zoomedSafeAreaBounds:
            return context.zoomedSafeAreaBounds
        }
    }
}

private extension CGRect {
    func _inset(by insets: EdgeInsets) -> CGRect {
        let left = CGFloat(insets.leading)
        let right = CGFloat(insets.trailing)
        let top = CGFloat(insets.top)
        let bottom = CGFloat(insets.bottom)

        return CGRect(
            x: origin.x + left,
            y: origin.y + top,
            width: max(0, size.width - left - right),
            height: max(0, size.height - top - bottom)
        )
    }

    static func _aspectFit(inside container: CGRect, sourceSize: CGSize) -> CGRect? {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let sourceAspect = sourceSize.width / sourceSize.height
        let containerAspect = container.width / max(container.height, 0.0001)

        let fitSize: CGSize
        if containerAspect > sourceAspect {
            // Container is wider than needed; fit by height.
            let height = container.height
            fitSize = CGSize(width: height * sourceAspect, height: height)
        } else {
            // Container is taller than needed; fit by width.
            let width = container.width
            fitSize = CGSize(width: width, height: width / sourceAspect)
        }

        return CGRect(
            x: container.midX - fitSize.width / 2,
            y: container.midY - fitSize.height / 2,
            width: fitSize.width,
            height: fitSize.height
        )
    }
}
