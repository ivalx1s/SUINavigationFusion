import Foundation

public enum NavigationRestoreFailure: Sendable {
    case missingDestination(key: NavigationDestinationKey)
    case decodeFailed(key: NavigationDestinationKey, errorDescription: String)
}

public struct NavigationRestorePolicy: Sendable {
    public enum Behavior: Sendable {
        /// Restore as much as possible: drop the invalid suffix and keep the successfully restored prefix.
        case dropSuffixAndContinue
        /// Clear all cached entries and show only the root.
        case clearAllAndShowRoot
    }

    public var behavior: Behavior
    public var onFailure: @MainActor (NavigationRestoreFailure) -> Void

    public init(
        behavior: Behavior = .dropSuffixAndContinue,
        onFailure: @escaping @MainActor (NavigationRestoreFailure) -> Void = { _ in }
    ) {
        self.behavior = behavior
        self.onFailure = onFailure
    }
}

