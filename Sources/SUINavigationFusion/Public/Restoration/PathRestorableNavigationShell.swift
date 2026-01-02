import SwiftUI
import Foundation

/// A navigation shell that supports caching and restoring the navigation stack (Option 4).
///
/// The stack is restored from a persisted snapshot of `{destinationKey, payload}` entries.
/// Only `navigator.push(route:)` participates in restoration; `navigator.push(_ view:)` is treated as transient.
@MainActor
public struct PathRestorableNavigationShell<Root: View>: View {
    private let id: String
    private let idScope: NavigationStackIDScope
    private let providedNavigator: Navigator?
    private let configuration: TopNavigationBarConfiguration
    private let store: NavigationStackStateStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let policy: NavigationRestorePolicy
    private let destinations: (NavigationDestinationRegistry) -> Void
    private let rootBuilder: (Navigator) -> Root

    @SceneStorage("SUINavigationFusion.NavigationStack.sceneID") private var sceneID = UUID().uuidString

    public init(
        id: String,
        idScope: NavigationStackIDScope = .global,
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
        self.idScope = idScope
        self.providedNavigator = navigator
        self.configuration = configuration
        self.store = store
        self.encoder = encoder
        self.decoder = decoder
        self.policy = policy
        self.destinations = destinations
        self.rootBuilder = root
    }

    private var effectiveID: String {
        switch idScope {
        case .global:
            return id
        case .scene:
            return "\(id).\(sceneID)"
        }
    }

    public var body: some View {
        _PathRestorableNavigationShellCore(
            id: effectiveID,
            navigator: providedNavigator,
            configuration: configuration,
            store: store,
            encoder: encoder,
            decoder: decoder,
            policy: policy,
            destinations: destinations,
            root: rootBuilder
        )
    }
}

@MainActor
private struct _PathRestorableNavigationShellCore<Root: View>: View {
    private let id: String
    private let providedNavigator: Navigator?
    private let configuration: TopNavigationBarConfiguration
    private let rootBuilder: (Navigator) -> Root

    @StateObject private var ownedNavigator = Navigator()
    @StateObject private var restorationState: _RestorationState

    init(
        id: String,
        navigator: Navigator?,
        configuration: TopNavigationBarConfiguration,
        store: NavigationStackStateStore,
        encoder: JSONEncoder,
        decoder: JSONDecoder,
        policy: NavigationRestorePolicy,
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

    var body: some View {
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
