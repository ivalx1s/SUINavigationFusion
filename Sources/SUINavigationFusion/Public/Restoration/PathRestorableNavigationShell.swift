import SwiftUI
import Foundation

/// A navigation shell that supports caching and restoring the navigation stack (Option 4).
///
/// The stack is restored from a persisted snapshot of `{destinationKey, payload}` entries.
/// Only `navigator.push(route:)` participates in restoration; `navigator.push(_ view:)` is treated as transient.
@MainActor
public struct PathRestorableNavigationShell<Root: View>: View {
    private let id: String
    private let providedNavigator: Navigator?
    private let configuration: TopNavigationBarConfiguration
    private let rootBuilder: (Navigator) -> Root

    @StateObject private var ownedNavigator = Navigator()
    @StateObject private var restorationState: _RestorationState

    public init(
        id: String,
        navigator: Navigator? = nil,
        configuration: TopNavigationBarConfiguration = .defaultMaterial,
        store: NavigationStackStateStore = UserDefaultsNavigationStackStore(),
        encoder: JSONEncoder = .init(),
        decoder: JSONDecoder = .init(),
        policy: NavigationRestorePolicy = .init(),
        destinations: @escaping (NavigationDestinationRegistry) -> Void,
        @ViewBuilder root: @escaping (Navigator) -> Root
    ) {
        self.id = id
        self.providedNavigator = navigator
        self.configuration = configuration
        self.rootBuilder = root

        _restorationState = StateObject(
            wrappedValue: _RestorationState(
                id: id,
                store: store,
                encoder: encoder,
                decoder: decoder,
                policy: policy,
                destinations: destinations
            )
        )
    }

    private var navigator: Navigator {
        providedNavigator ?? ownedNavigator
    }

    public var body: some View {
        VStack {
            _NavigationRoot(
                navigator: navigator,
                configuration: configuration,
                restorationContext: restorationState.context,
                root: { rootBuilder(navigator) }
            )
        }
        .id(id)
        .ignoresSafeArea(.all, edges: .top)
    }
}

@MainActor
private final class _RestorationState: ObservableObject {
    let context: _NavigationStackRestorationContext

    init(
        id: String,
        store: NavigationStackStateStore,
        encoder: JSONEncoder,
        decoder: JSONDecoder,
        policy: NavigationRestorePolicy,
        destinations: (NavigationDestinationRegistry) -> Void
    ) {
        let registry = NavigationDestinationRegistry()
        destinations(registry)

        self.context = _NavigationStackRestorationContext(
            id: id,
            store: store,
            registry: registry,
            encoder: encoder,
            decoder: decoder,
            policy: policy
        )
    }
}
