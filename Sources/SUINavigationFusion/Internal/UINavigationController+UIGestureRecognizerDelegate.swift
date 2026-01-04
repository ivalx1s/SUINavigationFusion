#if canImport(UIKit)
import UIKit
#endif

/// Internal `UINavigationController` subclass used by SUINavigationFusion.
///
/// The library relies on UIKit navigation behavior (push/pop, interactive swipe-back).
/// `NCUINavigationController` installs itself as the interactive pop gesture delegate and consults
/// `NavigationBackGesturePolicyProviding` on the top hosting controller to support per-screen disabling.
public final class NCUINavigationController: UINavigationController {
    
}

extension NCUINavigationController: UIGestureRecognizerDelegate {
    public override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        interactivePopGestureRecognizer?.isEnabled = true
    }
    
    /// Enables the interactive back swipe only when:
    /// - the stack has more than one controller (there is something to pop), and
    /// - the top controller does not disable it via `NavigationBackGesturePolicyProviding`.
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard viewControllers.count > 1 else { return false }
        if let top = topViewController as? NavigationBackGesturePolicyProviding {
            return !top.disablesBackGesture
        }
        return true
    }
}
