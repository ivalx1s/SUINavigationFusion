#if canImport(UIKit)
import UIKit
#endif

public final class NCUINavigationController: UINavigationController {
    
}

extension NCUINavigationController: UIGestureRecognizerDelegate {
    public override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        interactivePopGestureRecognizer?.isEnabled = true
    }
    
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard viewControllers.count > 1 else { return false }
        if let top = topViewController as? NavigationBackGesturePolicyProviding {
            return !top.disablesBackGesture
        }
        return true
    }
}
