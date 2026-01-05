import SwiftUI
import Combine
import Foundation

@MainActor
struct _NavigationPathDriver {
    /// Returns the current bound navigation path.
    ///
    /// This is a closure (instead of a stored `Binding`) so the driver can be installed from SwiftUI
    /// without leaking SwiftUI generic types into `Navigator`.
    let get: () -> SUINavigationPath

    /// Sets a new bound navigation path.
    ///
    /// - Parameter path: The updated path.
    /// - Parameter animated: Whether the update should be considered animated.
    ///
    /// The actual UIKit animation is performed by the hosting shell when it reconciles the UIKit stack to match
    /// the new path (using the current SwiftUI transaction).
    let set: (_ path: SUINavigationPath, _ animated: Bool) -> Void

    /// Encoder used to serialize route payloads into `SUINavigationPath.Element.payload`.
    let encoder: JSONEncoder
}

/// A thin, observable wrapper around a `NCUINavigationController` that lets
/// SwiftUI code perform imperative navigation without touching UIKit APIs.
///
/// Typical usage (inside a view, coordinator or your preferable entity that receives `navigator`):
/// ```swift
/// navigator.push(ProfileView())
/// navigator.presentSheet { nav in
///     EditProfileView(navigator: nav)
/// }
/// ```
///
///
/// ### Key capabilities
/// * `push` / `pop` / `popToRoot` / `pop(levels:)`
///
/// `Navigator` instances are created for you by `NavigationHost` or manually
/// when more controls is needed over underlying `NCUINavigationController`.
@available(iOS 14, *)
@MainActor
public final class Navigator: ObservableObject, Equatable, Hashable {
    
    private final class WeakBox<T: AnyObject> {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }
    
    private var attachedNavigationControllers: [WeakBox<NCUINavigationController>] = []
    
    private weak var resolvedNavigationController: NCUINavigationController?
    public let resolveNavigationController: () -> NCUINavigationController?
    
    var navigationPageTransitionProgress: NavigationPageTransitionProgress?
    /// Shared top-bar configuration for this navigation stack.
    /// Updated by `NavigationShell` and injected into every hosted screen.
    let topNavigationBarConfigurationStore = TopNavigationBarConfigurationStore()

    /// Internal restoration context installed by restorable shells.
    ///
    /// Non-`nil` only when the navigator is hosted by `PathRestorableNavigationShell` / `RestorableNavigationShell`.
    var _restorationContext: _NavigationStackRestorationContext?

    /// Internal routing registry installed by typed/restorable shells.
    ///
    /// Non-`nil` when the navigator is hosted by `TypedNavigationShell`,
    /// `PathRestorableNavigationShell`, or `RestorableNavigationShell`.
    var _routingRegistry: NavigationDestinationRegistry?

    /// Optional driver that makes this navigator path-driven (NavigationStack-like).
    ///
    /// When set, stack operations (`push(route:)`, `pop`, etc.) mutate the bound `SUINavigationPath`
    /// instead of directly pushing/popping UIKit view controllers.
    ///
    /// Path-driven stacks must be route-only (every screen above root must be representable as a path element).
    var _pathDriver: _NavigationPathDriver?

    private struct _PendingPathMutation {
        /// Whether the caller requested an animated update.
        ///
        /// In path-driven navigation, this is translated into a SwiftUI transaction (`disablesAnimations`)
        /// and then mirrored to UIKit by the hosting shell when reconciling the stack.
        let animated: Bool

        /// Optional transition request for the next path-driven push (e.g. iOS 18+ `.zoom(...)`).
        ///
        /// This is an ephemeral style hint and is **not persisted**.
        let transition: SUINavigationTransition?

        /// Mutation to apply to the bound `SUINavigationPath`.
        let mutation: (inout SUINavigationPath) -> Void
    }

    /// Path mutations that were requested while a UIKit transition was still in flight.
    ///
    /// UIKit is not re-entrant: pushing/popping while `UINavigationController` is still transitioning can
    /// corrupt the stack and break animations (especially for iOS 18+ zoom interactive dismiss).
    ///
    /// We queue path mutations and replay them once the transition finishes.
    private var pendingPathMutations: [_PendingPathMutation] = []

    /// Tracks the transition coordinator we attached a completion handler to, so we only schedule one flush
    /// per in-flight transition.
    private weak var pendingMutationCoordinator: UIViewControllerTransitionCoordinator?

    /// Internal registry of UIKit views used as anchors for iOS 18+ native zoom transitions.
    ///
    /// SwiftUI code registers anchors via `.suinavZoomSource(id:)` / `.suinavZoomDestination(id:)`.
    /// The library then resolves the actual `UIView` at transition time (push + pop) by id.
    let _zoomViewRegistry = _NavigationZoomViewRegistry()
    
    // MARK: - Equatable
    
    nonisolated public static func == (lhs: Navigator, rhs: Navigator) -> Bool {
        lhs === rhs
    }
    
    // MARK: - Hashable
    
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    
    /// Creates a navigator that will adopt a navigation controller later,
    /// e.g. from inside `_NavigationRoot`.
    public convenience init() {
        self.init(resolveNavigationController: { nil })
    }
    
    public init(
        resolveNavigationController: @escaping () -> NCUINavigationController?
    ) {
        self.resolvedNavigationController = nil
        self.resolveNavigationController = resolveNavigationController
        debugPrint("[NavigationCore] [Navigator] navigator initialized")
    }
    
    deinit {
        debugPrint("[NavigationCore] [Navigator] navigator de-initialized")
    }

    func attachNavigationController(_ navigationController: NCUINavigationController) {
        attachedNavigationControllers.removeAll { $0.value == nil || $0.value === navigationController }
        attachedNavigationControllers.append(WeakBox(navigationController))

        resolvedNavigationController = navigationController
    }

    func detachNavigationController(_ navigationController: NCUINavigationController) {
        attachedNavigationControllers.removeAll { $0.value == nil || $0.value === navigationController }

        if resolvedNavigationController === navigationController {
            resolvedNavigationController = nil
        }
    }
    
    private func currentNavigationController() -> NCUINavigationController? {
        attachedNavigationControllers.removeAll { $0.value == nil }
        
        if let top = attachedNavigationControllers.last?.value {
            return top
        }

        if let cached = resolvedNavigationController {
            return cached
        }
        
        let resolved = resolveNavigationController()
        if resolvedNavigationController == nil { resolvedNavigationController = resolved }
        
        return resolved
    }
    
    // MARK: - Stack operations

    private func mutatePath(
        animated: Bool,
        transition: SUINavigationTransition? = nil,
        _ mutation: @escaping (inout SUINavigationPath) -> Void
    ) {
        guard let driver = _pathDriver else { return }

        // If UIKit is currently transitioning (interactive pop, zoom dismiss, animated push, etc.),
        // do not mutate the bound path immediately: SwiftUI would try to reconcile UIKit while the transition
        // is still active, which can lead to stack corruption and broken animations.
        if let navigationController = currentNavigationController(),
           let coordinator = navigationController.transitionCoordinator {
            pendingPathMutations.append(.init(animated: animated, transition: transition, mutation: mutation))
            schedulePendingPathMutationFlush(using: coordinator)
            return
        }

        applyPathMutation(driver: driver, animated: animated, transition: transition, mutation)
    }

    private func applyPathMutation(
        driver: _NavigationPathDriver,
        animated: Bool,
        transition: SUINavigationTransition?,
        _ mutation: (inout SUINavigationPath) -> Void
    ) {
        var path = driver.get()
        mutation(&path)

        // Translate the caller’s intent into a SwiftUI transaction so the shell can mirror it
        // when reconciling UIKit (animate by default; allow disabling for deep links, restores, etc.).
        var transaction = Transaction()
        if animated {
            transaction.animation = .default
        } else {
            transaction.disablesAnimations = true
            transaction.animation = nil
        }
        if #available(iOS 17.0, *) {
            transaction.suinavigationTransition = transition
        }

        withTransaction(transaction) {
            driver.set(path, animated)
        }
    }

    private func schedulePendingPathMutationFlush(using coordinator: UIViewControllerTransitionCoordinator) {
        // Only schedule one flush per in-flight transition.
        guard pendingMutationCoordinator !== coordinator else { return }
        pendingMutationCoordinator = coordinator

        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.flushPendingPathMutationsIfPossible()
            }
        }
    }

    @MainActor
    private func flushPendingPathMutationsIfPossible() {
        guard let driver = _pathDriver else {
            pendingPathMutations.removeAll()
            pendingMutationCoordinator = nil
            return
        }
        guard !pendingPathMutations.isEmpty else {
            pendingMutationCoordinator = nil
            return
        }

        // If a transition is still active (or a new one started), wait for its completion.
        if let navigationController = currentNavigationController(),
           let coordinator = navigationController.transitionCoordinator {
            schedulePendingPathMutationFlush(using: coordinator)
            return
        }

        let mutations = pendingPathMutations
        pendingPathMutations.removeAll()
        pendingMutationCoordinator = nil

        // Apply all mutations to the latest path snapshot and publish once.
        //
        // If multiple actions were requested while transitioning, coalescing into a single state update is
        // the safest behavior (mirrors SwiftUI: last update wins, UIKit reconciles once).
        var path = driver.get()
        for pending in mutations {
            pending.mutation(&path)
        }

        // Use the last mutation’s “style” intent for the coalesced update.
        let last = mutations.last
        applyPathMutation(
            driver: driver,
            animated: last?.animated ?? false,
            transition: last?.transition,
            { $0 = path }
        )
    }

    func _makeHostingController(
        content: AnyView,
        disableBackGesture: Bool,
        restorationInfo: _NavigationRestorationInfo?
    ) -> UIViewController {
        let progress = NavigationPageTransitionProgress()
        let decoratedContent = Color.clear.overlay { content }
            .topNavigationBar(isRoot: false)
            .environmentObject(progress)
            .environmentObject(topNavigationBarConfigurationStore)
            .environmentObject(self)

        return NavigationShellHostingController(
            rootView: decoratedContent,
            navigationPageTransitionProgress: progress,
            disablesBackGesture: disableBackGesture,
            restorationInfo: restorationInfo
        )
    }
    
    /// Pushes a SwiftUI view onto the navigation stack.
    ///
    /// - Parameters:
    ///   - view: The SwiftUI `View` to push.
    ///   - animated: `true` to animate the transition (default), `false` for an
    ///     immediate push.
    ///   - disableBackGesture: `true` to disable interactive back gestures for the pushed screen.
    ///   - transition: Optional transition request (e.g. `.zoom(...)` on iOS 18+). Defaults to `nil` (system push).
    ///
    /// `transition` is applied only for imperative stacks. In path-driven navigation, this API is not supported.
    public func push<V: View>(
        _ view: V,
        animated: Bool = true,
        disableBackGesture: Bool = false,
        transition: SUINavigationTransition? = nil
    ) {
        if _pathDriver != nil {
            assertionFailure("Navigator.push(_:) is not supported in path-driven navigation. Use push(route:) or mutate the bound SUINavigationPath.")
            return
        }
        guard let navigationController = currentNavigationController() else { return }

        let controller = _makeHostingController(
            content: AnyView(view),
            disableBackGesture: disableBackGesture,
            restorationInfo: nil
        )

        if animated {
            _applyTransitionIfNeeded(
                transition,
                to: controller,
                disableBackGesture: disableBackGesture,
                sourceViewController: navigationController.topViewController
            )
        }
        navigationController.pushViewController(controller, animated: animated)
        navigationController.setNavigationBarHidden(true, animated: false)
        _restorationContext?.syncSnapshot(from: navigationController)
    }

    /// Pushes a serializable route onto the navigation stack.
    ///
    /// Route-based pushes require:
    /// - the route type to conform to `NavigationPathItem` (so it has a stable destination key), and
    /// - a typed destination registry installed by:
    /// - `TypedNavigationShell` (typed routing only)
    /// - `PathRestorableNavigationShell` / `RestorableNavigationShell` (typed routing + persistence)
    ///
    /// - Parameters:
    ///   - route: The serializable route payload to push.
    ///   - animated: Whether to animate the push.
    ///   - disableBackGesture: Whether to disable interactive back gestures for the pushed screen.
    ///   - transition: Optional transition request (e.g. `.zoom(...)` on iOS 18+). Defaults to `nil` (system push).
    ///
    /// If the navigator is not hosted by a typed/restorable shell, this call asserts in debug builds and no-ops.
    ///
    /// In path-driven navigation, this method mutates the bound `SUINavigationPath` (the shell reconciles UIKit).
    /// If UIKit is currently transitioning (animated push/pop, interactive dismiss), the path mutation is deferred
    /// until the transition completes to avoid re-entrancy issues that can corrupt the stack.
    public func push<Route: NavigationPathItem>(
        route: Route,
        animated: Bool = true,
        disableBackGesture: Bool = false,
        transition: SUINavigationTransition? = nil
    ) {
        guard let registry = _routingRegistry else {
            assertionFailure("Navigator.push(route:) requires a typed navigation shell (TypedNavigationShell / PathRestorableNavigationShell / RestorableNavigationShell).")
            return
        }

        guard let key = registry.key(for: Route.self) else {
            assertionFailure("No destination registered for route type: \(Route.self).")
            return
        }

        guard let registration = registry.registration(for: key) else {
            assertionFailure("No destination registered for key: \(key.rawValue).")
            return
        }
        guard registration.payloadTypeID == ObjectIdentifier(Route.self) else {
            assertionFailure("Destination key '\(key.rawValue)' is registered for a different route type.")
            return
        }

        if let driver = _pathDriver {
            do {
                let payload = try driver.encoder.encode(route)
                mutatePath(animated: animated, transition: transition) { path in
                    path.append(.init(key: key, payload: payload, disableBackGesture: disableBackGesture))
                }
            } catch {
                assertionFailure("Failed to encode route payload for path-driven navigation: \(error).")
            }
            return
        }

        guard let navigationController = currentNavigationController() else { return }

        let view = registration.buildViewFromValue(route)
        let effectiveTransition = transition ?? registration.defaultTransitionFromValue?(route)

        let restorationInfo: _NavigationRestorationInfo?
        if let restorationContext = _restorationContext {
            do {
                let payload = try restorationContext.encoder.encode(route)
                restorationInfo = _NavigationRestorationInfo(key: key, payload: payload)
            } catch {
                assertionFailure("Failed to encode route payload for restoration: \(error).")
                return
            }
        } else {
            restorationInfo = nil
        }

        let controller = _makeHostingController(
            content: view,
            disableBackGesture: disableBackGesture,
            restorationInfo: restorationInfo
        )

        if animated {
            _applyTransitionIfNeeded(
                effectiveTransition,
                to: controller,
                disableBackGesture: disableBackGesture,
                sourceViewController: navigationController.topViewController
            )
        }
        navigationController.pushViewController(controller, animated: animated)
        navigationController.setNavigationBarHidden(true, animated: false)
        _restorationContext?.syncSnapshot(from: navigationController)
    }

    /// Clears cached/restorable navigation state for the current navigation shell (no-op otherwise).
    public func clearCachedStack() {
        _restorationContext?.clear()
    }
    
    /// Pops the top view controller.
    ///
    /// - Parameter animated: `true` to animate the pop (default).
    public func pop() {
        if _pathDriver != nil {
            mutatePath(animated: true) { $0.removeLast(1) }
            return
        }
        guard let navigationController = currentNavigationController() else { return }
        navigationController.popViewController(animated: true)
        _restorationContext?.syncSnapshot(from: navigationController)
    }
    
    /// Pops the top view controller.
    ///
    /// - Parameter animated: `true` to animate the pop (default).
    public func popNonAnimated() {
        if _pathDriver != nil {
            mutatePath(animated: false) { $0.removeLast(1) }
            return
        }
        guard let navigationController = currentNavigationController() else { return }
        navigationController.popViewController(animated: false)
        _restorationContext?.syncSnapshot(from: navigationController)
    }
    
    /// Pops all view controllers until only the root remains.
    ///
    /// - Parameter animated: `true` to animate the transition (default).
    public func popToRoot(animated: Bool = true) {
        if _pathDriver != nil {
            mutatePath(animated: animated) { $0.clear() }
            return
        }
        guard let navigationController = currentNavigationController() else { return }
        navigationController.popToRootViewController(animated: animated)
        _restorationContext?.syncSnapshot(from: navigationController)
    }
    
    /// Pops a specific number of levels up the navigation stack.
    ///
    /// - Parameters:
    ///   - levels: How many view controllers to pop (must be `> 0`).
    ///   - animated: `true` to animate the transition (default).
    ///
    /// If `levels` is greater than or equal to the current depth, the call
    /// behaves like `popToRoot(animated:)`.
    public func pop(levels: Int, animated: Bool = true) {
        if _pathDriver != nil {
            mutatePath(animated: animated) { $0.removeLast(levels) }
            return
        }
        guard levels > 0, let navigationController = currentNavigationController() else { return }
        let depth = navigationController.viewControllers.count
        if levels >= depth - 1 {
            navigationController.popToRootViewController(animated: animated)
        } else {
            let target = navigationController.viewControllers[depth - levels - 1]
            navigationController.popToViewController(target, animated: animated)
        }

        _restorationContext?.syncSnapshot(from: navigationController)
    }
    
    // MARK: - Transitions

    /// Applies a navigation transition request to a UIKit view controller, if supported.
    ///
    /// For iOS 18+ zoom transitions, UIKit requires the *destination* controller to provide:
    /// - a `preferredTransition` configured as `.zoom(...)`
    /// - a `sourceViewProvider` closure that resolves the source view on demand (UIKit calls it for push and pop)
    ///
    /// For all other cases (unsupported OS, missing anchors, `.standard`), this method is a no-op.
    func _applyTransitionIfNeeded(
        _ transition: SUINavigationTransition?,
        to controller: UIViewController,
        disableBackGesture: Bool,
        sourceViewController: UIViewController? = nil
    ) {
        #if canImport(UIKit)
        guard let transition else { return }
        guard case .zoom(let zoom) = transition else { return }
        guard #available(iOS 18.0, *) else { return }

        // Avoid surprising “zoom from center” by requiring the source view to exist *in the current source VC*
        // at push time. If we return a view from a different hierarchy, UIKit can fall back to a degraded animation
        // (often perceived as a fade).
        if let sourceRoot = sourceViewController?.view {
            guard _zoomViewRegistry.sourceView(for: zoom.sourceID, inHierarchyOf: sourceRoot) != nil else { return }
        } else {
            guard _zoomViewRegistry.sourceView(for: zoom.sourceID) != nil else { return }
        }

        if let provider = controller as? _NavigationZoomTransitionInfoProviding {
            provider._suinavZoomTransitionInfo = _NavigationZoomTransitionInfo(
                sourceID: zoom.sourceID,
                destinationID: zoom.destinationID
            )
        }

        let options = UIViewController.Transition.ZoomOptions()

        // Keep the library’s “no interactive back” contract consistent:
        // - `disableBackGesture` disables edge-swipe back
        // - the same flag also disables zoom’s interactive dismiss gestures
        //
        // This ensures you can treat `disableBackGesture` as “no interactive dismissal” regardless of transition type.
        if disableBackGesture {
            options.interactiveDismissShouldBegin = { _ in false }
        } else if zoom.interactiveDismissPolicy._isPureSystemDefault == false {
            // UIKit calls the interactive-dismiss hook with no reference to the view controller.
            // Capture the destination controller weakly and resolve the destination anchor rect at interaction time.
            options.interactiveDismissShouldBegin = { [weak self, weak controller] interactionContext in
                guard let self else { return interactionContext.willBegin }
                guard let controller else { return interactionContext.willBegin }
                assert(Thread.isMainThread)

                guard let controllerView = controller.view else { return interactionContext.willBegin }

                let destinationAnchorFrame: CGRect?
                let overrideDestinationID = (controller as? _NavigationZoomDynamicIDsProviding)?._suinavZoomDynamicDestinationID
                if
                    let overrideDestinationID,
                    let destinationView = self._zoomViewRegistry.destinationView(for: overrideDestinationID, inHierarchyOf: controllerView)
                {
                    destinationAnchorFrame = destinationView.convert(destinationView.bounds, to: controllerView)
                } else if
                    let destinationID = zoom.destinationID,
                    let destinationView = self._zoomViewRegistry.destinationView(for: destinationID, inHierarchyOf: controllerView)
                {
                    destinationAnchorFrame = destinationView.convert(destinationView.bounds, to: controllerView)
                } else {
                    destinationAnchorFrame = nil
                }

                let context = SUINavigationZoomInteractiveDismissContext(
                    systemWillBegin: interactionContext.willBegin,
                    location: interactionContext.location,
                    velocity: interactionContext.velocity,
                    destinationAnchorFrame: destinationAnchorFrame
                )
                return zoom.interactiveDismissPolicy._evaluate(context)
            }
        }

        if zoom.alignmentRectPolicy._isPureSystemDefault == false {
            options.alignmentRectProvider = { [weak self] context in
                guard let self else { return nil }
                assert(Thread.isMainThread)

                guard let zoomedView = context.zoomedViewController.view else { return nil }
                let safeInsets = zoomedView.safeAreaInsets
                let safeAreaBounds = zoomedView.bounds.inset(by: safeInsets)

                let destinationAnchorFrame: CGRect?
                let overrideDestinationID = (context.zoomedViewController as? _NavigationZoomDynamicIDsProviding)?._suinavZoomDynamicDestinationID
                if
                    let overrideDestinationID,
                    let destinationView = self._zoomViewRegistry.destinationView(for: overrideDestinationID, inHierarchyOf: zoomedView)
                {
                    destinationAnchorFrame = destinationView.convert(destinationView.bounds, to: zoomedView)
                } else if
                    let destinationID = zoom.destinationID,
                    let destinationView = self._zoomViewRegistry.destinationView(for: destinationID, inHierarchyOf: zoomedView)
                {
                    destinationAnchorFrame = destinationView.convert(destinationView.bounds, to: zoomedView)
                } else {
                    destinationAnchorFrame = nil
                }

                let policyContext = SUINavigationZoomAlignmentRectContext(
                    zoomedViewBounds: zoomedView.bounds,
                    zoomedSafeAreaBounds: safeAreaBounds,
                    sourceViewSize: context.sourceView.bounds.size,
                    destinationAnchorFrame: destinationAnchorFrame
                )

                return zoom.alignmentRectPolicy._evaluate(policyContext)
            }
        }

        if let dimmingColor = zoom.dimmingColor {
            options.dimmingColor = UIColor(dimmingColor)
        }

        if let dimmingVisualEffect = zoom.dimmingVisualEffect {
            switch dimmingVisualEffect {
            case .blur(let style):
                options.dimmingVisualEffect = UIBlurEffect(style: style._uikitStyle)
            }
        }

        controller.preferredTransition = .zoom(options: options) { [weak self] providerContext in
            guard let self else { return nil }
            assert(Thread.isMainThread)

            // UIKit calls this closure when it needs the “source” view (both on push and on pop).
            // Use the provided source view controller to select the correct anchor view.
            guard let sourceRoot = providerContext.sourceViewController.view else { return nil }

            // Apple’s zoom transition API recommends using the provider context to decide which view to zoom from
            // when dismissing. For example, a detail screen can page between items without leaving the screen,
            // so the correct thumbnail to zoom back to can change over time.
            //
            // We support this by letting the zoomed SwiftUI screen publish its current id into the hosting
            // controller (see `.suinavZoomDismissTo(id:)`). If no override is set, we fall back to the static
            // `zoom.sourceID` captured when the controller was pushed.
            let overrideSourceID = (providerContext.zoomedViewController as? _NavigationZoomDynamicIDsProviding)?._suinavZoomDynamicSourceID
            if
                let overrideSourceID,
                let view = self._zoomViewRegistry.sourceView(for: overrideSourceID, inHierarchyOf: sourceRoot)
            {
                return view
            }

            return self._zoomViewRegistry.sourceView(for: zoom.sourceID, inHierarchyOf: sourceRoot)
        }
        #endif
    }

}
