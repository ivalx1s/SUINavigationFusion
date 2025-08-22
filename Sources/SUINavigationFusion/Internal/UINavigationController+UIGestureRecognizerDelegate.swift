#if canImport(UIKit)
import UIKit
#endif

public final class NCUINavigationController: UINavigationController {
    
}

extension NCUINavigationController: UIGestureRecognizerDelegate {
    public override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}
