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
    private weak var resolvedNavigationController: NCUINavigationController?
    public let resolveNavigationController: () -> NCUINavigationController?
    
    var navigationPageTransitionProgress: NavigationPageTransitionProgress?
    var topNavigationBarConfiguration: TopNavigationBarConfiguration?
    
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

    func setNavigationController(_ navigationController: NCUINavigationController) {
        resolvedNavigationController = navigationController
    }
    
    private func currentNavigationController() -> NCUINavigationController? {
        if let navigationController = resolvedNavigationController { return navigationController }
        let navigationController = resolveNavigationController()
        if resolvedNavigationController == nil { resolvedNavigationController = navigationController }
        return navigationController
    }
    
    // MARK: - Stack operations
    
    /// Pushes a SwiftUI view onto the navigation stack.
    ///
    /// - Parameters:
    ///   - view: The SwiftUI `View` to push.
    ///   - animated: `true` to animate the transition (default), `false` for an
    ///     immediate push.
    public func push<V: View>(_ view: V, animated: Bool = true, disableBackGesture: Bool = false) {
        guard let navigationController = currentNavigationController() else { return }
        guard let navigatorConfiguration = topNavigationBarConfiguration else { return }
        let progress = NavigationPageTransitionProgress()
        let content  = Color.clear.overlay(content: { view })
            .topNavigationBar(isRoot: false)
            .environmentObject(progress)
            .topNavigationBarConfiguration(navigatorConfiguration)
            .environmentObject(self)
        let hosting  = NavigationShellHostingController(rootView: content, navigationPageTransitionProgress: progress)
        
        navigationController.pushViewController(hosting, animated: animated)
        navigationController.setNavigationBarHidden(true, animated: false)
        if let gesture = navigationController.interactivePopGestureRecognizer {
            gesture.isEnabled = !disableBackGesture
        }
    }
    
    /// Pops the top view controller.
    ///
    /// - Parameter animated: `true` to animate the pop (default).
    public func pop() {
        currentNavigationController()?.popViewController(animated: true)
    }
    
    /// Pops the top view controller.
    ///
    /// - Parameter animated: `true` to animate the pop (default).
    public func popNonAnimated() {
        currentNavigationController()?.popViewController(animated: false)
    }
    
    /// Pops all view controllers until only the root remains.
    ///
    /// - Parameter animated: `true` to animate the transition (default).
    public func popToRoot(animated: Bool = true) {
        currentNavigationController()?.popToRootViewController(animated: animated)
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
    }
    
}
