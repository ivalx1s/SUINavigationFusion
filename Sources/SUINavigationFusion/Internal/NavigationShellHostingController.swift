import SwiftUI

@MainActor
protocol NavigationTransitionProgressHolder: AnyObject {
    var navigationPageTransitionProgress: NavigationPageTransitionProgress { get }
}

@MainActor
final class NavigationShellHostingController<Content: View>: UIHostingController<Content>, NavigationTransitionProgressHolder {
    let navigationPageTransitionProgress: NavigationPageTransitionProgress
    
    init(rootView: Content, navigationPageTransitionProgress: NavigationPageTransitionProgress) {
        self.navigationPageTransitionProgress = navigationPageTransitionProgress
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
