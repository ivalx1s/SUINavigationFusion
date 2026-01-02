import SwiftUI

/// A registry of restorable destinations (Option 4 – type-erased, NavigationPath-like).
///
/// The registry maps:
/// - payload type → destination key (used when pushing)
/// - destination key → decode + view builder (used when restoring)
///
/// Register destinations once at the root of a restorable navigation shell.
@MainActor
public final class NavigationDestinationRegistry {
    struct Registration {
        let key: NavigationDestinationKey
        let payloadTypeID: ObjectIdentifier
        let buildViewFromValue: (Any) -> AnyView
        let buildViewFromPayload: (Data, JSONDecoder) throws -> AnyView
    }

    private var registrationsByKey: [NavigationDestinationKey: Registration] = [:]
    private var keyByType: [ObjectIdentifier: NavigationDestinationKey] = [:]

    public init() {}

    public func register<Item: NavigationPathItem, Screen: View>(
        _ type: Item.Type,
        key: NavigationDestinationKey,
        aliases: [NavigationDestinationKey] = [],
        @ViewBuilder destination: @escaping (Item) -> Screen
    ) {
        let registration = Registration(
            key: key,
            payloadTypeID: ObjectIdentifier(type),
            buildViewFromValue: { value in
                AnyView(destination(value as! Item))
            },
            buildViewFromPayload: { payload, decoder in
                let value = try decoder.decode(Item.self, from: payload)
                return AnyView(destination(value))
            }
        )

        registrationsByKey[key] = registration
        for alias in aliases {
            registrationsByKey[alias] = registration
        }

        keyByType[ObjectIdentifier(type)] = key
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
