import SwiftUI

/// A SwiftUI transaction key used to request a navigation transition for the next path-driven update.
///
/// This is primarily used for “router-owned path” navigation:
/// an external entity mutates a bound `SUINavigationPath`, and `_NavigationRoot` mirrors that mutation
/// to the UIKit stack. The active transaction is the only reliable place to pass ephemeral “style”
/// information (like a zoom transition) without persisting it.
///
/// - Important:
///   The value is **not persisted** and applies only to the update performed in the same transaction.
@available(iOS 17.0, *)
public struct SUINavigationTransitionKey: TransactionKey {
    /// `SUINavigationTransition` is intended to be used from the main actor (SwiftUI view updates).
    /// Marked `nonisolated(unsafe)` to satisfy Swift 6 concurrency checking for a static key default.
    public nonisolated(unsafe) static let defaultValue: SUINavigationTransition? = nil
}

@available(iOS 17.0, *)
public extension Transaction {
    /// Requested navigation transition for the current SwiftUI update.
    var suinavigationTransition: SUINavigationTransition? {
        get { self[SUINavigationTransitionKey.self] }
        set { self[SUINavigationTransitionKey.self] = newValue }
    }
}

/// Runs `body` in a transaction that requests the given navigation transition.
///
/// Use this to drive iOS 18+ zoom transitions from an external router when mutating a bound `SUINavigationPath`:
///
/// ```swift
/// withSUINavigationTransition(.zoom(id: photo.id)) {
///     router.path.append(PhotoRoute(id: photo.id))
/// }
/// ```
///
/// If you need to combine this with other transaction configuration (e.g. `disablesAnimations`),
/// set both values on the same `Transaction` and use `withTransaction(_:)` directly.
@discardableResult
@available(iOS 17.0, *)
public func withSUINavigationTransition<Result>(
    _ transition: SUINavigationTransition?,
    _ body: () throws -> Result
) rethrows -> Result {
    var transaction = Transaction()
    transaction.suinavigationTransition = transition
    return try withTransaction(transaction, body)
}
