import SwiftUI
import Foundation

/// A convenience wrapper around `PathRestorableNavigationShell` (Option 3).
///
/// Use this when your app has a single, typed `Route` (often an enum) and you want an exhaustive `switch`.
/// Use `idScope: .scene` to isolate snapshots per window/scene when supporting multi-window apps.
@MainActor
public struct RestorableNavigationShell<Route: NavigationRoute>: View {
    private let id: String
    private let idScope: NavigationStackIDScope
    private let providedNavigator: Navigator?
    private let configuration: TopNavigationBarConfiguration
    private let store: NavigationStackStateStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let policy: NavigationRestorePolicy
    private let key: NavigationDestinationKey
    private let aliases: [NavigationDestinationKey]
    private let rootBuilder: (Navigator) -> AnyView
    private let destinationBuilder: (Route) -> AnyView

    /// Creates a restorable navigation shell (Option 3 – a single `Route` type).
    ///
    /// - Parameters:
    ///   - id: Base persistence identifier for this navigation stack.
    ///   - idScope: Controls whether `id` is global (`.global`) or scoped per scene/window (`.scene`).
    ///   - navigator: Optional external `Navigator` instance to reuse.
    ///   - configuration: Shared top bar styling configuration for this stack.
    ///   - store: Storage backend for persisted navigation snapshots.
    ///   - encoder: Encoder used to serialize route payloads and snapshots.
    ///   - decoder: Decoder used to deserialize route payloads and snapshots.
    ///   - policy: Failure policy for missing destinations or decode failures.
    ///   - key: Stable destination key for the single `Route` type (persisted in snapshots).
    ///   - aliases: Historical keys that should be treated as equivalent (useful when renaming keys).
    ///   - root: Root screen builder (not persisted).
    ///   - destination: Builds screens for route values.
    public init<Root: View, Destination: View>(
        id: String,
        idScope: NavigationStackIDScope = .global,
        navigator: Navigator? = nil,
        configuration: TopNavigationBarConfiguration = .defaultMaterial,
        store: NavigationStackStateStore = UserDefaultsNavigationStackStore(),
        encoder: JSONEncoder = .init(),
        decoder: JSONDecoder = .init(),
        policy: NavigationRestorePolicy = .init(),
        key: NavigationDestinationKey = .type(Route.self),
        aliases: [NavigationDestinationKey] = [],
        @ViewBuilder root: @escaping (Navigator) -> Root,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self.id = id
        self.idScope = idScope
        self.providedNavigator = navigator
        self.configuration = configuration
        self.store = store
        self.encoder = encoder
        self.decoder = decoder
        self.policy = policy
        self.key = key
        self.aliases = aliases
        self.rootBuilder = { navigator in AnyView(root(navigator)) }
        self.destinationBuilder = { route in AnyView(destination(route)) }
    }

    public var body: some View {
        PathRestorableNavigationShell(
            id: id,
            idScope: idScope,
            navigator: providedNavigator,
            configuration: configuration,
            store: store,
            encoder: encoder,
            decoder: decoder,
            policy: policy,
            destinations: { registry in
                registry.register(Route.self, key: key, aliases: aliases) { route in
                    destinationBuilder(route)
                }
            },
            root: rootBuilder
        )
    }
}
