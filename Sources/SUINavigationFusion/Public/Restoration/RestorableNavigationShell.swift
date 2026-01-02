import SwiftUI
import Foundation

/// A convenience wrapper around `PathRestorableNavigationShell` (Option 3).
///
/// Use this when your app has a single, typed `Route` (often an enum) and you want an exhaustive `switch`.
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
