import Foundation

/// A non-fatal restoration issue encountered while rebuilding a cached navigation stack.
///
/// Restoration failures are handled according to `NavigationRestorePolicy`.
public enum NavigationRestoreFailure: Sendable {
    /// No destination is registered for the key stored in the snapshot.
    case missingDestination(key: NavigationDestinationKey)
    /// A destination was found, but decoding the route payload failed.
    case decodeFailed(key: NavigationDestinationKey, errorDescription: String)
}

/// Controls how the restoration engine reacts to failures when rebuilding a cached navigation stack.
///
/// By default, restoration is best-effort: the engine restores the successfully decoded prefix of the stack
/// and drops the invalid suffix.
public struct NavigationRestorePolicy: Sendable {
    public enum Behavior: Sendable {
        /// Restore as much as possible: drop the invalid suffix and keep the successfully restored prefix.
        case dropSuffixAndContinue
        /// Clear all cached entries and show only the root.
        case clearAllAndShowRoot
    }

    /// Defines what happens after a restoration failure.
    public var behavior: Behavior

    /// Called when restoration encounters an issue (missing destination / decode failure).
    ///
    /// Use this hook for logging or diagnostics. Runs on the main actor.
    public var onFailure: @MainActor (NavigationRestoreFailure) -> Void

    public init(
        behavior: Behavior = .dropSuffixAndContinue,
        onFailure: @escaping @MainActor (NavigationRestoreFailure) -> Void = { _ in }
    ) {
        self.behavior = behavior
        self.onFailure = onFailure
    }
}
