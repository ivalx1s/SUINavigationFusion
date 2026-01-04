import SwiftUI

/// A lightweight abstraction used to register route destinations into a navigation stack.
///
/// Feature modules can depend on this protocol instead of a concrete registry type.
/// The app (or a shell) decides which concrete registry implementation to use.
///
/// See also: `NavigationDestinations` for composing multiple registration bundles.
@MainActor
public protocol NavigationDestinationRegistering: AnyObject {
    /// Registers a destination for a route payload type.
    ///
    /// - Parameters:
    ///   - type: The `NavigationPathItem` payload type you will push via `navigator.push(route:)`.
    ///   - key: A stable identifier persisted in navigation snapshots. Prefer explicit, namespaced keys.
    ///   - aliases: Historical keys that should be treated as equivalent (useful when renaming keys).
    ///   - destination: Builds the SwiftUI screen for the given payload.
    func register<Item: NavigationPathItem, Screen: View>(
        _ type: Item.Type,
        key: NavigationDestinationKey,
        aliases: [NavigationDestinationKey],
        @ViewBuilder destination: @escaping (Item) -> Screen
    )
}

public extension NavigationDestinationRegistering {
    /// Registers a destination using the payload type’s `destinationKey`.
    ///
    /// This helps prevent mismatches between a type’s declared key and the key used for registration.
    func register<Item: NavigationPathItem, Screen: View>(
        _ type: Item.Type,
        aliases: [NavigationDestinationKey] = [],
        @ViewBuilder destination: @escaping (Item) -> Screen
    ) {
        register(type, key: Item.destinationKey, aliases: aliases, destination: destination)
    }

    /// Convenience overload with `aliases` defaulting to `[]`.
    func register<Item: NavigationPathItem, Screen: View>(
        _ type: Item.Type,
        key: NavigationDestinationKey,
        @ViewBuilder destination: @escaping (Item) -> Screen
    ) {
        register(type, key: key, aliases: [], destination: destination)
    }
}
