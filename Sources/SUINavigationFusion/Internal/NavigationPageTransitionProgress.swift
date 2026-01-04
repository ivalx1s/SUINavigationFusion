import SwiftUI
import Combine

@MainActor
/// A tiny observable object used to propagate transition progress into SwiftUI.
///
/// SUINavigationFusion samples UIKit navigation transitions (including interactive swipe-back) and exposes
/// a normalized progress value (0 → 1). The custom top bar uses this to coordinate cross-fades between
/// bars of the source and destination screens.
///
/// - Important:
///   UIKit transition callbacks can happen while SwiftUI is computing view bodies. Publishing changes from
///   within a view update triggers a runtime warning:
///   "Publishing changes from within view updates is not allowed, this will cause undefined behavior."
///
///   To keep SwiftUI stable, updates are coalesced and published on the next run loop tick via `setProgress(_:)`.
final class NavigationPageTransitionProgress: ObservableObject {
    @Published private(set) var progress: CGFloat = 0

    private var pendingProgress: CGFloat?
    private var isPublishScheduled: Bool = false

    /// Sets transition progress, publishing on the next run loop tick.
    ///
    /// This method coalesces multiple calls within the same tick by keeping only the latest value.
    func setProgress(_ progress: CGFloat) {
        pendingProgress = progress
        guard !isPublishScheduled else { return }
        isPublishScheduled = true

        Task { @MainActor in
            // Defer publishing to escape SwiftUI’s current view update cycle.
            await Task.yield()

            self.isPublishScheduled = false
            guard let pending = self.pendingProgress else { return }
            self.pendingProgress = nil
            self.progress = pending
        }
    }
}
