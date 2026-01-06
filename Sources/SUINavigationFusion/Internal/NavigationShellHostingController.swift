import SwiftUI

@MainActor
protocol NavigationTransitionProgressHolder: AnyObject {
    var navigationPageTransitionProgress: NavigationPageTransitionProgress { get }
}

@MainActor
protocol NavigationBackGesturePolicyProviding: AnyObject {
    var disablesBackGesture: Bool { get }
}

@MainActor
final class NavigationShellHostingController<Content: View>: UIHostingController<Content>, NavigationTransitionProgressHolder, NavigationBackGesturePolicyProviding {
    let navigationPageTransitionProgress: NavigationPageTransitionProgress
    let disablesBackGesture: Bool
    let _restorationInfo: _NavigationRestorationInfo?
    /// Ephemeral zoom transition metadata set when this controller is pushed with `.zoom(...)`.
    ///
    /// Used by `_NavigationRoot.Coordinator` to hide/show anchor views during the transition.
    var _suinavZoomTransitionInfo: _NavigationZoomTransitionInfo?

    /// Dynamic zoom source id override for iOS 18+ zoom transitions.
    ///
    /// This allows SwiftUI detail screens that can change their “current item” (without leaving the screen)
    /// to update the id that UIKit should zoom back to on dismiss.
    var _suinavZoomDynamicSourceID: AnyHashable?

    /// Dynamic zoom destination id override for iOS 18+ zoom transitions.
    ///
    /// When the destination hero view changes (e.g. paging between items), this keeps alignment-rect lookups
    /// consistent with the currently displayed content.
    var _suinavZoomDynamicDestinationID: AnyHashable?

    /// Transition-scoped frozen zoom ids (iOS 18+ zoom).
    ///
    /// UIKit may request the source view multiple times during a single transition (notably for interactive
    /// dismiss + completion). If SwiftUI updates the dynamic ids mid-transition, the effective ids can change
    /// between provider calls, which can lead to undefined behavior (including looping transitions).
    ///
    /// SUINavigationFusion freezes the effective ids for the duration of each transition and clears them
    /// when the transition finishes/cancels.
    var _suinavZoomFrozenSourceID: AnyHashable?
    var _suinavZoomFrozenDestinationID: AnyHashable?
    
    init(
        rootView: Content,
        navigationPageTransitionProgress: NavigationPageTransitionProgress,
        disablesBackGesture: Bool = false,
        restorationInfo: _NavigationRestorationInfo? = nil
    ) {
        self.navigationPageTransitionProgress = navigationPageTransitionProgress
        self.disablesBackGesture = disablesBackGesture
        self._restorationInfo = restorationInfo
        self._suinavZoomTransitionInfo = nil
        self._suinavZoomDynamicSourceID = nil
        self._suinavZoomDynamicDestinationID = nil
        self._suinavZoomFrozenSourceID = nil
        self._suinavZoomFrozenDestinationID = nil
        super.init(rootView: rootView)
    }
    
    @MainActor
    @objc required dynamic init?(coder: NSCoder) { fatalError() }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        
        if #available(iOS 15.0, *) {
            navigationController?.navigationBar.isHidden = true
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
}

extension NavigationShellHostingController: _NavigationRestorable {}
extension NavigationShellHostingController: _NavigationZoomTransitionInfoProviding {}
extension NavigationShellHostingController: _NavigationZoomDynamicIDsProviding {}
extension NavigationShellHostingController: _NavigationZoomFrozenIDsProviding {}
