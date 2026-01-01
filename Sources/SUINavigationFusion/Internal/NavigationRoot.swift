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
    
    init(
        configuration: TopNavigationBarConfiguration,
        @ViewBuilder root: @escaping (Navigator) -> Root
    ) {
        self.navigator = nil
        self.rootBuilder = root
        self.configuration = configuration
    }
    
    init(
        navigator: Navigator,
        configuration: TopNavigationBarConfiguration,
        @ViewBuilder root: @escaping () -> Root
    ) {
        self.navigator = navigator
        self.rootBuilder = { _ in root() }
        self.configuration = configuration
    }
    
    // MARK: - Coordinator
    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate {
        let progress = NavigationPageTransitionProgress()
        var injectedNavigator: Navigator?

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
                    from.navigationPageTransitionProgress.progress = 0        // fully visible
                    to.navigationPageTransitionProgress.progress   = 0.3      // start slightly visible
                } else {
                    from.navigationPageTransitionProgress.progress = 0.7      // almost faded
                    to.navigationPageTransitionProgress.progress   = 0        // visible
                }
            }
            
            startDisplayLink()
            
            transitionContext.animate(alongsideTransition: nil) { [weak self] context in
                self?.clamp(cancelled: context.isCancelled)
                self?.stopDisplayLink()
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
                    from.navigationPageTransitionProgress.progress = clampedProgress
                    to.navigationPageTransitionProgress.progress   = max(0, 0.3 - 0.3 * clampedProgress)
                } else {
                    from.navigationPageTransitionProgress.progress = min(1, 0.7 + 0.3 * clampedProgress)
                    to.navigationPageTransitionProgress.progress   = 0
                }
            }
            
            progress.progress = clampedProgress
        }
        
        private func clamp(cancelled: Bool) {
            guard let coordinator = transitionCoordinator else { return }
            if let from = coordinator.viewController(forKey: .from) as? NavigationTransitionProgressHolder,
               let to   = coordinator.viewController(forKey: .to)   as? NavigationTransitionProgressHolder {
                if cancelled {                    // Return to fully‑visible source bar and hide the destination bar.
                    from.navigationPageTransitionProgress.progress = 0   // visible
                    to.navigationPageTransitionProgress.progress   = 1   // hidden
                } else {
                    // Normal completion.
                    from.navigationPageTransitionProgress.progress = 1   // hidden
                    to.navigationPageTransitionProgress.progress   = 0   // visible
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
        if let externalNavigator = navigator {
            let resolvedNavigationController = externalNavigator.resolveNavigationController()
            let navigationController = resolvedNavigationController ?? NCUINavigationController()

            if resolvedNavigationController == nil {
                externalNavigator.attachNavigationController(navigationController)
            }

            let transitionProgress = context.coordinator.progress
            context.coordinator.injectedNavigator = externalNavigator

            externalNavigator.navigationPageTransitionProgress = transitionProgress
            externalNavigator.topNavigationBarConfigurationStore.setConfiguration(configuration)
            let rootController = makeRootViewController(
                for: externalNavigator,
                progress: transitionProgress
            )
            navigationController.viewControllers = [rootController]
            navigationController.setNavigationBarHidden(true, animated: false)
            navigationController.delegate = context.coordinator
            return navigationController
        } else {
            let navigationController = NCUINavigationController()
            let autoInjectedNavigator = Navigator(resolveNavigationController: { [weak navigationController] in
                navigationController
            })
            autoInjectedNavigator.attachNavigationController(navigationController)

            let transitionProgress = context.coordinator.progress
            context.coordinator.injectedNavigator = autoInjectedNavigator

            autoInjectedNavigator.navigationPageTransitionProgress = transitionProgress
            autoInjectedNavigator.topNavigationBarConfigurationStore.setConfiguration(configuration)
            let rootController = makeRootViewController(
                for: autoInjectedNavigator,
                progress: transitionProgress
            )
            navigationController.viewControllers = [rootController]
            navigationController.setNavigationBarHidden(true, animated: false)
            navigationController.delegate = context.coordinator
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
