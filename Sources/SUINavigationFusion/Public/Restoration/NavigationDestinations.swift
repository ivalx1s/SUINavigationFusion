import SwiftUI

/// A composable bundle of destination registrations for typed navigation.
///
/// Use this type to decouple feature modules from a concrete navigation stack:
/// each module can expose a `NavigationDestinations` value, and the app can merge them
/// when configuring a shell.
///
/// The bundle is applied once during shell initialization and is expected to be deterministic
/// (avoid side effects).
public struct NavigationDestinations {
    private let apply: @MainActor (NavigationDestinationRegistering) -> Void

    /// Creates a destination bundle from a registration closure.
    public init(_ apply: @escaping @MainActor (NavigationDestinationRegistering) -> Void) {
        self.apply = apply
    }

    /// An empty bundle (registers nothing).
    public static var empty: NavigationDestinations {
        .init { _ in }
    }

    /// Applies this bundle into a registry/registerer.
    @MainActor
    public func register(into registerer: NavigationDestinationRegistering) {
        apply(registerer)
    }

    /// Returns a bundle that applies `self` and then `other` into the same registerer.
    public func merging(_ other: NavigationDestinations) -> NavigationDestinations {
        let leftApply = apply
        let rightApply = other.apply
        return NavigationDestinations { registerer in
            leftApply(registerer)
            rightApply(registerer)
        }
    }
}
