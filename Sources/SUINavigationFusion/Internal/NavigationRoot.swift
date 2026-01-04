//
//  Navigation.swift
//  Core
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Combine


/**
 `NavigationRoot` is the UIKit bridge that powers the public‐facing
 `Navigation` API.
 
 It owns an `NCUINavigationController`, exposing it to SwiftUI
 code through a lightweight `Navigator` service object.  All push/pop and
 presentation operations requested by child views are funneled through that
 service, so application code never has to talk to UIKit directly.
 
 ### Responsibilities
 1. **Environment injection** – Injects a shared `TopNavigationBarConfigurationStore`
 into the SwiftUI environment, ensuring every `TopNavigationBar` created in this
 stack shares the same style and can react to runtime configuration updates.
 2. **Root view hosting** – Wraps the caller‑supplied `Root` view in a
 `UIHostingController`, hides the system navigation bar, and installs the
 custom bar via the `.topNavigationBar(isRoot:)` modifier.
 3. **Transition progress propagation** – Acts as the
 `UINavigationControllerDelegate`, sampling interactive and non‑interactive
 transitions.  Progress updates are forwarded to any `NavProgressHolder`
 instances so custom bars can synchronize their animations with the page
 swipe.
 
 End‑users of the library **do not** interact with `NavigationRoot`
 directly; they simply create a `Navigation { … }` container and let the
 internals handle the rest.
 */
@available(iOS 15, *)
struct _NavigationRoot<Root: View>: UIViewControllerRepresentable {
    private let navigator: Navigator?
    private let rootBuilder: ((Navigator) -> Root)
    
    /**
     The style configuration that will be applied to every *top navigation bar*
     within the navigation stack created by this `Navigation` representable.
     
     This representable updates a shared `TopNavigationBarConfigurationStore` on
     the `Navigator` and injects it into every hosted screen. As a result:
     - The top bar reads configuration from a single source of truth.
     - Updating `NavigationShell(configuration:)` at runtime updates the top bar
       for the currently visible screen as well as any pushed screens.
     */
    private let configuration: TopNavigationBarConfiguration
    private let routingRegistry: NavigationDestinationRegistry?
    private let restorationContext: _NavigationStackRestorationContext?
    private let pathDriver: _NavigationPathDriver?
    
    init(
        configuration: TopNavigationBarConfiguration,
        routingRegistry: NavigationDestinationRegistry? = nil,
        restorationContext: _NavigationStackRestorationContext? = nil,
        pathDriver: _NavigationPathDriver? = nil,
        @ViewBuilder root: @escaping (Navigator) -> Root
    ) {
        self.navigator = nil
        self.rootBuilder = root
        self.configuration = configuration
        self.routingRegistry = routingRegistry
        self.restorationContext = restorationContext
        self.pathDriver = pathDriver
    }
    
    init(
        navigator: Navigator,
        configuration: TopNavigationBarConfiguration,
        routingRegistry: NavigationDestinationRegistry? = nil,
        restorationContext: _NavigationStackRestorationContext? = nil,
        pathDriver: _NavigationPathDriver? = nil,
        @ViewBuilder root: @escaping () -> Root
    ) {
        self.navigator = navigator
        self.rootBuilder = { _ in root() }
        self.configuration = configuration
        self.routingRegistry = routingRegistry
        self.restorationContext = restorationContext
        self.pathDriver = pathDriver
    }
    
    // MARK: - Coordinator
    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate {
        fileprivate struct PendingReconcile {
            /// The latest desired path observed while UIKit was still transitioning.
            ///
            /// We cannot safely reconcile UIKit to a new desired path while a transition is in flight
            /// (interactive pop, zoom dismiss, animated push, etc.). Doing so can corrupt the navigation stack.
            ///
            /// Instead, we stash the desired path and re-emit it once the transition finishes, so the next
            /// SwiftUI update can reconcile safely.
            let desiredPath: SUINavigationPath

            /// Whether animations were disabled for the SwiftUI update that produced `desiredPath`.
            ///
            /// `_NavigationRoot.updateUIViewController` mirrors SwiftUI’s `NavigationStack(path:)` behavior:
            /// it animates by default and disables animations when `Transaction.disablesAnimations == true`.
            let disablesAnimations: Bool

            /// Optional transition request attached to the SwiftUI transaction (e.g. iOS 18+ zoom).
            ///
            /// This is an ephemeral style hint and is **not persisted**.
            let requestedTransition: SUINavigationTransition?
        }

        let progress = NavigationPageTransitionProgress()
        var injectedNavigator: Navigator?
        var restorationContext: _NavigationStackRestorationContext?
        var didAttemptRestore: Bool = false
        var isRestoring: Bool = false
        var isApplyingPath: Bool = false
        var pathDriver: _NavigationPathDriver?
        fileprivate var pendingReconcile: PendingReconcile?
        private var pendingPathUpdate: SUINavigationPath?
        private var pendingPathUpdateTask: Task<Void, Never>?
        private var transitionStartBoundPath: SUINavigationPath?
        fileprivate var isTransitionInFlight: Bool = false

        private weak var transitionCoordinator: UIViewControllerTransitionCoordinator?
        private var displayLink: CADisplayLink?
        private var isPushTransition: Bool = true
        
        private var transitionStartTime: CFTimeInterval = 0
        private var transitionDuration: TimeInterval   = 0
        private var initialPercentComplete: CGFloat    = 0
        private var completionCurve: UIView.AnimationCurve = .linear
        private var completionVelocity: CGFloat = 0
        
        // UINavigationControllerDelegate
        public func navigationController(_ navigationController: UINavigationController,
                                         willShow viewController: UIViewController,
                                         animated: Bool) {
            guard let transitionContext = navigationController.transitionCoordinator else { return }
            transitionCoordinator = transitionContext
            transitionStartBoundPath = pathDriver?.get()
            isTransitionInFlight = true
            
            transitionStartTime      = CACurrentMediaTime()
            transitionDuration       = transitionContext.transitionDuration
            initialPercentComplete   = CGFloat(transitionContext.percentComplete)
            completionCurve        = transitionContext.completionCurve
            completionVelocity      = transitionContext.completionVelocity
            
            transitionContext.notifyWhenInteractionChanges { [weak self] context in
                guard let self = self else { return }
                self.transitionStartTime      = CACurrentMediaTime()
                self.initialPercentComplete   = CGFloat(context.percentComplete)
                self.transitionDuration       = context.transitionDuration
                self.completionCurve          = context.completionCurve
                self.completionVelocity       = context.completionVelocity

                // Path-driven stacks are “NavigationStack-like”: an external router owns `SUINavigationPath`,
                // and UIKit must follow it. For gesture-driven navigation (interactive pop/zoom dismiss),
                // UIKit becomes the source of truth.
                //
                // iOS 18+ zoom interactive dismiss has a relatively long completion phase: `didShow` is invoked
                // noticeably later than the moment the UI looks “done”. If we only update the bound path in
                // `didShow`, the external router stays stale for a while, and user actions in that window may
                // build on an outdated path and corrupt the stack.
                //
                // To close that window, when the interactive portion ends we proactively update the bound path
                // to the *expected* result (pop or cancel). `_NavigationRoot.updateUIViewController` guards against
                // reconciling while UIKit is still transitioning, so this update does not trigger re-entrant pops.
                guard
                    let pathDriver = self.pathDriver,
                    self.restorationContext != nil,
                    !self.isApplyingPath,
                    !self.isPushTransition,
                    let startBoundPath = self.transitionStartBoundPath
                else { return }

                // Only apply if the router hasn’t already changed the path during the gesture.
                if pathDriver.get() != startBoundPath { return }

                // If the interaction was cancelled, UIKit will stay on the same screen, so there is nothing to sync.
                guard context.isCancelled == false else { return }

                var expected = startBoundPath
                expected.removeLast(1)
                self.scheduleBoundPathUpdate(expected)
            }
            
            let navigationControllerForIndices = navigationController
            
            if
                let fromIndex = navigationControllerForIndices.viewControllers.firstIndex(of: transitionContext.viewController(forKey: .from)!),
                let toIndex   = navigationControllerForIndices.viewControllers.firstIndex(of: transitionContext.viewController(forKey: .to)!) {
                isPushTransition = toIndex > fromIndex
            } else {
                isPushTransition = true
            }
            
            if let from = transitionContext.viewController(forKey: .from) as? NavigationTransitionProgressHolder,
               let to   = transitionContext.viewController(forKey: .to)   as? NavigationTransitionProgressHolder {
                
                if isPushTransition {
                    from.navigationPageTransitionProgress.setProgress(0)        // fully visible
                    to.navigationPageTransitionProgress.setProgress(0.3)      // start slightly visible
                } else {
                    from.navigationPageTransitionProgress.setProgress(0.7)      // almost faded
                    to.navigationPageTransitionProgress.setProgress(0)        // visible
                }
            }
            
            startDisplayLink()
            
            transitionContext.animate(alongsideTransition: nil) { [weak self] context in
                self?.clamp(cancelled: context.isCancelled)
                self?.stopDisplayLink()
                self?.transitionCoordinator = nil
                self?.isTransitionInFlight = false

                // If path reconciliation was deferred while UIKit was transitioning, re-emit the desired path now.
                // This triggers a SwiftUI update *after* UIKit finished the transition, allowing safe reconciliation.
                self?.flushPendingReconcileIfNeeded()
            }
        }

        public func navigationController(
            _ navigationController: UINavigationController,
            didShow viewController: UIViewController,
            animated: Bool
        ) {
            let startBoundPath = transitionStartBoundPath
            transitionStartBoundPath = nil
            isTransitionInFlight = false
            transitionCoordinator = nil
            guard !isRestoring, let navigationController = navigationController as? NCUINavigationController else { return }
            guard let restorationContext else { return }

            let (path, _) = restorationContext.syncSnapshot(from: navigationController)

            // In path-driven mode, the UIKit stack is the source of truth for gesture-driven changes.
            // Update the bound path on every `didShow` (e.g. interactive swipe-back) to keep external routers in sync.
            guard let pathDriver, !isApplyingPath else { return }
            // Compare-and-swap: only overwrite the bound path if it still matches what we observed
            // at the start of the transition. If an external router changed the path mid-transition,
            // do not clobber it here; the next SwiftUI update will reconcile UIKit to the new path.
            if let startBoundPath, pathDriver.get() != startBoundPath {
                // Router changed path during the transition; do not overwrite.
            } else if pathDriver.get() != path {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    pathDriver.set(path, false)
                }
            }

            // `pendingReconcile` is flushed in the transition completion callback. Keep `didShow` focused on
            // syncing the authoritative UIKit stack back into the bound path.
        }

        /// Re-emits a deferred desired path after UIKit finishes the current transition.
        ///
        /// Path-driven navigation must avoid UIKit re-entrancy: reconciling while a transition is in-flight can
        /// corrupt the stack. `_NavigationRoot.updateUIViewController` stashes the desired path when that happens.
        ///
        /// This method applies the stashed desired path once the transition completes, but only if it is still the
        /// router’s current intent (compare-and-swap). This prevents resurrecting stale paths after gesture-driven pops.
        private func flushPendingReconcileIfNeeded() {
            guard let pathDriver, let pendingReconcile else { return }
            self.pendingReconcile = nil

            // Only re-emit if the router didn’t change the path while UIKit was transitioning.
            guard pathDriver.get() == pendingReconcile.desiredPath else { return }
            Task { @MainActor in
                // Defer to escape any SwiftUI view update triggered by UIKit transition callbacks.
                await Task.yield()

                var transaction = Transaction()
                transaction.disablesAnimations = pendingReconcile.disablesAnimations
                if #available(iOS 17.0, *) {
                    transaction.suinavigationTransition = pendingReconcile.requestedTransition
                }
                withTransaction(transaction) {
                    pathDriver.set(pendingReconcile.desiredPath, !pendingReconcile.disablesAnimations)
                }
            }
        }

        /// Updates the bound `SUINavigationPath` on the next run loop tick.
        ///
        /// Calling `pathDriver.set(...)` synchronously from within `updateUIViewController` can trigger:
        /// "Publishing changes from within view updates is not allowed".
        /// Deferring the write keeps SwiftUI’s update cycle stable.
        @MainActor
        func scheduleBoundPathUpdate(_ path: SUINavigationPath) {
            guard pathDriver != nil else { return }
            pendingPathUpdate = path

            pendingPathUpdateTask?.cancel()
            pendingPathUpdateTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                guard let pathDriver = self.pathDriver, let pendingPathUpdate = self.pendingPathUpdate else { return }
                self.pendingPathUpdate = nil

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    pathDriver.set(pendingPathUpdate, false)
                }
            }
        }
        
        private func applyCurve(_ timeFraction: CGFloat, curve: UIView.AnimationCurve) -> CGFloat {
            let timing: CAMediaTimingFunction
            switch curve {
            case .easeIn:
                timing = CAMediaTimingFunction(name: .easeIn)
            case .easeOut:
                timing = CAMediaTimingFunction(name: .easeOut)
            case .easeInOut:
                timing = CAMediaTimingFunction(name: .easeInEaseOut)
            case .linear:
                timing = CAMediaTimingFunction(name: .linear)
            @unknown default:
                timing = CAMediaTimingFunction(name: .linear)
            }
            
            return timing.value(at: timeFraction)
        }
        
        // MARK: - Display-link sampling
        @objc private func tick() {
            guard let coordinatorContext = transitionCoordinator else { return }
            
            let linearProgress: CGFloat
            if coordinatorContext.isInteractive {
                linearProgress = CGFloat(coordinatorContext.percentComplete)
                transitionStartTime    = CACurrentMediaTime()
                initialPercentComplete = linearProgress
            } else {
                let elapsed = CACurrentMediaTime() - transitionStartTime
                let target: CGFloat = coordinatorContext.isCancelled ? 0 : 1
                let baseLinear = elapsed / max(0.0001, transitionDuration)
                
                let velocityScale = max(1, 1 + abs(completionVelocity) * 0.7)
                let acceleratedLinear = min(1, baseLinear * velocityScale)
                
                let eased = applyCurve(acceleratedLinear, curve: completionCurve)
                linearProgress = initialPercentComplete + (target - initialPercentComplete) * eased
            }
            
            let clampedProgress = min(max(linearProgress, 0), 1)
            
            if let from = coordinatorContext.viewController(forKey: .from) as? NavigationTransitionProgressHolder,
               let to   = coordinatorContext.viewController(forKey: .to)   as? NavigationTransitionProgressHolder {
                
                if isPushTransition {
                    from.navigationPageTransitionProgress.setProgress(clampedProgress)
                    to.navigationPageTransitionProgress.setProgress(max(0, 0.3 - 0.3 * clampedProgress))
                } else {
                    from.navigationPageTransitionProgress.setProgress(min(1, 0.7 + 0.3 * clampedProgress))
                    to.navigationPageTransitionProgress.setProgress(0)
                }
            }
            
            progress.setProgress(clampedProgress)
        }
        
        private func clamp(cancelled: Bool) {
            guard let coordinator = transitionCoordinator else { return }
            if let from = coordinator.viewController(forKey: .from) as? NavigationTransitionProgressHolder,
               let to   = coordinator.viewController(forKey: .to)   as? NavigationTransitionProgressHolder {
                if cancelled {                    // Return to fully‑visible source bar and hide the destination bar.
                    from.navigationPageTransitionProgress.setProgress(0)   // visible
                    to.navigationPageTransitionProgress.setProgress(1)   // hidden
                } else {
                    // Normal completion.
                    from.navigationPageTransitionProgress.setProgress(1)   // hidden
                    to.navigationPageTransitionProgress.setProgress(0)   // visible
                }
            }
        }
        
        private func startDisplayLink() {
            stopDisplayLink()
            displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink?.add(to: .main, forMode: .common)
        }
        
        @MainActor
        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    private func makeRootViewController(
        for navigator: Navigator,
        progress: NavigationPageTransitionProgress
    ) -> NavigationShellHostingController<DecoratedRoot<Root>> {
        let decoratedRoot = DecoratedRoot(
            content: rootBuilder(navigator),
            progress: progress,
            navigator: navigator
        )
        return NavigationShellHostingController(
            rootView: decoratedRoot,
            navigationPageTransitionProgress: progress
        )
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let effectiveRoutingRegistry = routingRegistry ?? restorationContext?.registry
        if let externalNavigator = navigator {
            let resolvedNavigationController = externalNavigator.resolveNavigationController()
            let navigationController = resolvedNavigationController ?? NCUINavigationController()

            if resolvedNavigationController == nil {
                externalNavigator.attachNavigationController(navigationController)
            }

            let transitionProgress = context.coordinator.progress
            context.coordinator.injectedNavigator = externalNavigator
            context.coordinator.restorationContext = restorationContext
            context.coordinator.pathDriver = pathDriver

            externalNavigator.navigationPageTransitionProgress = transitionProgress
            externalNavigator.topNavigationBarConfigurationStore.setConfiguration(configuration)
            externalNavigator._restorationContext = restorationContext
            externalNavigator._routingRegistry = effectiveRoutingRegistry
            externalNavigator._pathDriver = pathDriver
            let rootController = makeRootViewController(
                for: externalNavigator,
                progress: transitionProgress
            )
            navigationController.viewControllers = [rootController]
            navigationController.setNavigationBarHidden(true, animated: false)
            navigationController.delegate = context.coordinator

            if !context.coordinator.didAttemptRestore {
                context.coordinator.didAttemptRestore = true

                if let pathDriver {
                    guard let restorationContext else {
                        assertionFailure("Path-driven navigation requires a restoration context (use PathRestorableNavigationShell / RestorableNavigationShell).")
                        return navigationController
                    }

                    context.coordinator.isRestoring = true
                    context.coordinator.isApplyingPath = true

                    let desiredPath = pathDriver.get()
                    if desiredPath.elements.isEmpty {
                        restorationContext.restoreIfAvailable(
                            navigationController: navigationController,
                            rootController: rootController,
                            navigator: externalNavigator
                        )
                    } else {
                        let (restoredControllers, sanitizedPath) = restorationContext.buildViewControllers(
                            for: desiredPath,
                            navigator: externalNavigator
                        )
                        navigationController.setViewControllers([rootController] + restoredControllers, animated: false)
                        restorationContext.syncSnapshot(from: navigationController)

                        if sanitizedPath != desiredPath {
                            context.coordinator.scheduleBoundPathUpdate(sanitizedPath)
                        }
                    }

                    let (currentPath, _) = restorationContext.currentPath(from: navigationController)
                    if currentPath != desiredPath {
                        context.coordinator.scheduleBoundPathUpdate(currentPath)
                    }

                    context.coordinator.isApplyingPath = false
                    context.coordinator.isRestoring = false
                } else if let restorationContext {
                    context.coordinator.isRestoring = true
                    restorationContext.restoreIfAvailable(
                        navigationController: navigationController,
                        rootController: rootController,
                        navigator: externalNavigator
                    )
                    context.coordinator.isRestoring = false
                }
            }
            return navigationController
        } else {
            let navigationController = NCUINavigationController()
            let autoInjectedNavigator = Navigator(resolveNavigationController: { [weak navigationController] in
                navigationController
            })
            autoInjectedNavigator.attachNavigationController(navigationController)

            let transitionProgress = context.coordinator.progress
            context.coordinator.injectedNavigator = autoInjectedNavigator
            context.coordinator.restorationContext = restorationContext
            context.coordinator.pathDriver = pathDriver

            autoInjectedNavigator.navigationPageTransitionProgress = transitionProgress
            autoInjectedNavigator.topNavigationBarConfigurationStore.setConfiguration(configuration)
            autoInjectedNavigator._restorationContext = restorationContext
            autoInjectedNavigator._routingRegistry = effectiveRoutingRegistry
            autoInjectedNavigator._pathDriver = pathDriver
            let rootController = makeRootViewController(
                for: autoInjectedNavigator,
                progress: transitionProgress
            )
            navigationController.viewControllers = [rootController]
            navigationController.setNavigationBarHidden(true, animated: false)
            navigationController.delegate = context.coordinator

            if !context.coordinator.didAttemptRestore {
                context.coordinator.didAttemptRestore = true

                if let pathDriver {
                    guard let restorationContext else {
                        assertionFailure("Path-driven navigation requires a restoration context (use PathRestorableNavigationShell / RestorableNavigationShell).")
                        return navigationController
                    }

                    context.coordinator.isRestoring = true
                    context.coordinator.isApplyingPath = true

                    let desiredPath = pathDriver.get()
                    if desiredPath.elements.isEmpty {
                        restorationContext.restoreIfAvailable(
                            navigationController: navigationController,
                            rootController: rootController,
                            navigator: autoInjectedNavigator
                        )
                    } else {
                        let (restoredControllers, sanitizedPath) = restorationContext.buildViewControllers(
                            for: desiredPath,
                            navigator: autoInjectedNavigator
                        )
                        navigationController.setViewControllers([rootController] + restoredControllers, animated: false)
                        restorationContext.syncSnapshot(from: navigationController)

                        if sanitizedPath != desiredPath {
                            context.coordinator.scheduleBoundPathUpdate(sanitizedPath)
                        }
                    }

                    let (currentPath, _) = restorationContext.currentPath(from: navigationController)
                    if currentPath != desiredPath {
                        context.coordinator.scheduleBoundPathUpdate(currentPath)
                    }

                    context.coordinator.isApplyingPath = false
                    context.coordinator.isRestoring = false
                } else if let restorationContext {
                    context.coordinator.isRestoring = true
                    restorationContext.restoreIfAvailable(
                        navigationController: navigationController,
                        rootController: rootController,
                        navigator: autoInjectedNavigator
                    )
                    context.coordinator.isRestoring = false
                }
            }
            return navigationController
        }
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard
            let navigationController = controller as? NCUINavigationController,
            let hosting = navigationController.viewControllers.first as? NavigationShellHostingController<DecoratedRoot<Root>>,
            let navigator = context.coordinator.injectedNavigator
        else { return }

        let progress = context.coordinator.progress
        navigator.navigationPageTransitionProgress = progress
        navigator._routingRegistry = routingRegistry ?? restorationContext?.registry
        navigator._pathDriver = pathDriver
        context.coordinator.pathDriver = pathDriver
        // NOTE:
        // `TopNavigationBarConfigurationStore` is an `ObservableObject` (via `@Published configuration`).
        // Publishing changes synchronously from inside `updateUIViewController` triggers:
        // "Publishing changes from within view updates is not allowed, this will cause undefined behavior."
        //
        // Defer the publish to the next run loop tick to keep SwiftUI's update cycle stable.
        let updatedConfiguration = configuration
        Task { @MainActor in
            await Task.yield()
            navigator.topNavigationBarConfigurationStore.setConfiguration(updatedConfiguration)
        }

        // Path-driven navigation (NavigationStack-like):
        // If a path driver is installed, reconcile the UIKit stack to match the bound `SUINavigationPath`.
        if let pathDriver, let restorationContext, !context.coordinator.isRestoring {
            let desiredRaw = pathDriver.get()
            let desiredPath = (desiredRaw.schemaVersion == 1) ? desiredRaw : SUINavigationPath()
            // SwiftUI’s `NavigationStack(path:)` animates path-driven push/pop by default.
            //
            // We mirror that behavior by animating unless animations are explicitly disabled for this update.
            // To disable animations from an external router (e.g. deep links), wrap the path mutation in:
            // `withTransaction(Transaction(disablesAnimations: true)) { ... }`.
            let shouldAnimate = !context.transaction.disablesAnimations

            let (currentPath, isFullyRepresentable) = restorationContext.currentPath(from: navigationController)

            if desiredPath != currentPath || !isFullyRepresentable {
                // UIKit is not re-entrant: mutating the navigation stack while a transition is in flight can
                // corrupt the stack and break animations. This is especially noticeable for iOS 18+ zoom
                // interactive dismiss, where the completion phase can be relatively long.
                //
                // If UIKit is currently transitioning, stash the desired path and apply it once the transition finishes.
                if context.coordinator.isTransitionInFlight {
                    let requestedTransition: SUINavigationTransition?
                    if #available(iOS 17.0, *) {
                        requestedTransition = context.transaction.suinavigationTransition
                    } else {
                        requestedTransition = nil
                    }
                    context.coordinator.pendingReconcile = .init(
                        desiredPath: desiredPath,
                        disablesAnimations: context.transaction.disablesAnimations,
                        requestedTransition: requestedTransition
                    )
                } else {
                    context.coordinator.isApplyingPath = true
                    defer { context.coordinator.isApplyingPath = false }

                    let currentElements = currentPath.elements
                    let desiredElements = desiredPath.elements

                    if isFullyRepresentable,
                       desiredElements.count == currentElements.count + 1,
                       Array(desiredElements.prefix(currentElements.count)) == currentElements,
                       let element = desiredElements.last {
                        // Push one element.
                        let requestedTransition: SUINavigationTransition?
                        if #available(iOS 17.0, *) {
                            requestedTransition = context.transaction.suinavigationTransition
                        } else {
                            requestedTransition = nil
                        }
                        if let (controller, defaultTransition) = restorationContext.buildViewController(for: element, navigator: navigator) {
                            if shouldAnimate {
                                navigator._applyTransitionIfNeeded(
                                    requestedTransition ?? defaultTransition,
                                    to: controller,
                                    disableBackGesture: element.disableBackGesture
                                )
                            }
                            navigationController.pushViewController(controller, animated: shouldAnimate)
                        } else {
                            // If the appended element cannot be built (missing destination, decode failure, etc.),
                            // keep the current UIKit stack and only normalize the bound path according to policy:
                            // - `.dropSuffixAndContinue`: drop the invalid suffix (no UIKit changes)
                            // - `.clearAllAndShowRoot`: pop to root (clear stack)
                            let (_, sanitizedPath) = restorationContext.buildViewControllers(for: desiredPath, navigator: navigator)
                            if sanitizedPath.elements.isEmpty && !currentElements.isEmpty {
                                navigationController.popToRootViewController(animated: false)
                            }
                        }
                    } else if isFullyRepresentable,
                              currentElements.count == desiredElements.count + 1,
                              Array(currentElements.prefix(desiredElements.count)) == desiredElements {
                        // Pop one element.
                        navigationController.popViewController(animated: shouldAnimate)
                    } else if isFullyRepresentable,
                              desiredElements.count < currentElements.count,
                              Array(currentElements.prefix(desiredElements.count)) == desiredElements {
                        // Pop to a prefix (including root).
                        if desiredElements.isEmpty {
                            navigationController.popToRootViewController(animated: shouldAnimate)
                        } else {
                            let targetIndex = desiredElements.count
                            if navigationController.viewControllers.indices.contains(targetIndex) {
                                let target = navigationController.viewControllers[targetIndex]
                                navigationController.popToViewController(target, animated: shouldAnimate)
                            } else {
                                navigationController.popToRootViewController(animated: shouldAnimate)
                            }
                        }
                    } else {
                        // Big diff (or unrepresentable suffix) → rebuild stack from desired path.
                        let (controllers, _) = restorationContext.buildViewControllers(for: desiredPath, navigator: navigator)
                        navigationController.setViewControllers([hosting] + controllers, animated: false)
                    }

                    navigationController.setNavigationBarHidden(true, animated: false)

                    // Persist and (asynchronously) normalize the bound path to match the actual UIKit stack
                    // (policy may drop invalid suffix).
                    let (actualPath, _) = restorationContext.syncSnapshot(from: navigationController)
                    if actualPath != desiredRaw {
                        context.coordinator.scheduleBoundPathUpdate(actualPath)
                    }
                }
            }
        }

        let updatedRoot = DecoratedRoot(
            content: rootBuilder(navigator),
            progress: progress,
            navigator: navigator
        )

        hosting.rootView = updatedRoot
    }
    
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        guard
            let navigationController = uiViewController as? NCUINavigationController,
            let navigator = coordinator.injectedNavigator
        else {
            return
        }
        
        Task { @MainActor in
            navigator._pathDriver = nil
            navigator.detachNavigationController(navigationController)
        }
    }
}

@MainActor
private struct DecoratedRoot<Content: View>: View {
    let content: Content
    let progress: NavigationPageTransitionProgress
    let navigator: Navigator

    var body: some View {
        content
            .topNavigationBar(isRoot: true)
            .environmentObject(progress)
            .environmentObject(navigator)
            .environmentObject(navigator.topNavigationBarConfigurationStore)
    }
}
