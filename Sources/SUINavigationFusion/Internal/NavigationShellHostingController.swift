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
