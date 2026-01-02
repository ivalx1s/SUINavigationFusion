import SwiftUI
import Combine

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
    public func push<V: View>(_ view: V, animated: Bool = true, disableBackGesture: Bool = false) {
        guard let navigationController = currentNavigationController() else { return }

        let controller = _makeHostingController(
            content: AnyView(view),
            disableBackGesture: disableBackGesture,
            restorationInfo: nil
        )

        navigationController.pushViewController(controller, animated: animated)
        navigationController.setNavigationBarHidden(true, animated: false)
        _restorationContext?.syncSnapshot(from: navigationController)
    }

    /// Pushes a serializable route onto the navigation stack.
    ///
    /// Route-based pushes can participate in navigation stack caching/restoration when the stack
    /// is hosted by `PathRestorableNavigationShell` / `RestorableNavigationShell`.
    ///
    /// If the navigator is not hosted by a restorable shell, this call asserts in debug builds and no-ops.
    public func push<Route: NavigationRoute>(
        route: Route,
        animated: Bool = true,
        disableBackGesture: Bool = false
    ) {
        guard let navigationController = currentNavigationController() else { return }
        guard let restorationContext = _restorationContext else {
            assertionFailure("Navigator.push(route:) requires a restorable navigation shell.")
            return
        }

        guard let key = restorationContext.registry.key(for: Route.self) else {
            assertionFailure("No destination registered for route type: \(Route.self).")
            return
        }

        guard let registration = restorationContext.registry.registration(for: key) else {
            assertionFailure("No destination registered for key: \(key.rawValue).")
            return
        }
        guard registration.payloadTypeID == ObjectIdentifier(Route.self) else {
            assertionFailure("Destination key '\(key.rawValue)' is registered for a different route type.")
            return
        }

        let payload: Data
        do {
            payload = try restorationContext.encoder.encode(route)
        } catch {
            assertionFailure("Failed to encode route payload: \(error).")
            return
        }

        let view = registration.buildViewFromValue(route)
        let restorationInfo = _NavigationRestorationInfo(key: key, payload: payload)

        let controller = _makeHostingController(
            content: view,
            disableBackGesture: disableBackGesture,
            restorationInfo: restorationInfo
        )

        navigationController.pushViewController(controller, animated: animated)
        navigationController.setNavigationBarHidden(true, animated: false)
        restorationContext.syncSnapshot(from: navigationController)
    }

    /// Clears cached/restorable navigation state for the current navigation shell (no-op otherwise).
    public func clearCachedStack() {
        _restorationContext?.clear()
    }
    
    /// Pops the top view controller.
    ///
    /// - Parameter animated: `true` to animate the pop (default).
    public func pop() {
        guard let navigationController = currentNavigationController() else { return }
        navigationController.popViewController(animated: true)
        _restorationContext?.syncSnapshot(from: navigationController)
    }
    
    /// Pops the top view controller.
    ///
    /// - Parameter animated: `true` to animate the pop (default).
    public func popNonAnimated() {
        guard let navigationController = currentNavigationController() else { return }
        navigationController.popViewController(animated: false)
        _restorationContext?.syncSnapshot(from: navigationController)
    }
    
    /// Pops all view controllers until only the root remains.
    ///
    /// - Parameter animated: `true` to animate the transition (default).
    public func popToRoot(animated: Bool = true) {
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
    
}
