import SwiftUI

/// A registry of restorable destinations (Option 4 – type-erased, NavigationPath-like).
///
/// The registry maps:
/// - payload type → destination key (used when pushing)
/// - destination key → decode + view builder (used when restoring)
///
/// Register destinations once at the root of a restorable navigation shell.
@MainActor
public final class NavigationDestinationRegistry: NavigationDestinationRegistering {
    struct Registration {
        let key: NavigationDestinationKey
        let payloadTypeID: ObjectIdentifier
        let decodeValue: (Data, JSONDecoder) throws -> Any
        let buildViewFromValue: (Any) -> AnyView
        let defaultTransitionFromValue: ((Any) -> SUINavigationTransition?)?
    }

    private var registrationsByKey: [NavigationDestinationKey: Registration] = [:]
    private var keyByType: [ObjectIdentifier: NavigationDestinationKey] = [:]

    public init() {}

    /// Registers a restorable destination for a route payload type.
    ///
    /// Register destinations once at the root of a restorable navigation shell.
    ///
    /// - Parameters:
    ///   - type: The `Codable` payload type you will push via `navigator.push(route:)`.
    ///   - key: A stable identifier persisted in navigation snapshots. Prefer explicit, namespaced keys.
    ///   - aliases: Historical keys that should be treated as equivalent (useful when renaming keys).
    ///   - defaultTransition: Optional per-destination default transition (e.g. iOS 18+ zoom).
    ///     Used when no explicit transition is requested at the call site.
    ///   - destination: Builds the SwiftUI screen for the given payload.
    public func register<Item: NavigationPathItem, Screen: View>(
        _ type: Item.Type,
        key: NavigationDestinationKey,
        aliases: [NavigationDestinationKey] = [],
        defaultTransition: ((Item) -> SUINavigationTransition?)? = nil,
        @ViewBuilder destination: @escaping (Item) -> Screen
    ) {
        // If the payload type declares a key, prefer keeping registration consistent with it.
        // This is especially important for external routers building `SUINavigationPath` without a registry reference.
        if key != Item.destinationKey {
            assertionFailure(
                "Key mismatch for \(Item.self): registering '\(key.rawValue)' but \(Item.self).destinationKey is '\(Item.destinationKey.rawValue)'."
            )
        }

        let registration = Registration(
            key: key,
            payloadTypeID: ObjectIdentifier(type),
            decodeValue: { payload, decoder in
                try decoder.decode(Item.self, from: payload)
            },
            buildViewFromValue: { value in
                AnyView(destination(value as! Item))
            },
            defaultTransitionFromValue: defaultTransition.map { callback in
                { value in callback(value as! Item) }
            }
        )

        registrationsByKey[key] = registration
        for alias in aliases {
            registrationsByKey[alias] = registration
        }

        keyByType[ObjectIdentifier(type)] = key
    }

    /// Registers a destination using the payload type’s `destinationKey`.
    public func register<Item: NavigationPathItem, Screen: View>(
        _ type: Item.Type,
        aliases: [NavigationDestinationKey] = [],
        defaultTransition: ((Item) -> SUINavigationTransition?)? = nil,
        @ViewBuilder destination: @escaping (Item) -> Screen
    ) {
        register(type, key: Item.destinationKey, aliases: aliases, defaultTransition: defaultTransition, destination: destination)
    }

    func key<Item: NavigationPathItem>(for type: Item.Type) -> NavigationDestinationKey? {
        keyByType[ObjectIdentifier(type)]
    }

    func registration(for key: NavigationDestinationKey) -> Registration? {
        if let registration = registrationsByKey[key] {
            return registration
        }

        let normalized = key.normalized
        guard normalized != key else { return nil }
        return registrationsByKey[normalized]
    }
}
