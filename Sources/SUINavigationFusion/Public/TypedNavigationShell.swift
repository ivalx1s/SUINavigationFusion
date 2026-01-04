import SwiftUI

/// A navigation shell that supports typed route pushes via a destination registry (without persistence).
///
/// Use this when you want `navigator.push(route:)` (route payloads must conform to `NavigationPathItem`)
/// but do not need navigation stack caching/restoration.
/// For persisted restoration, use `PathRestorableNavigationShell` / `RestorableNavigationShell` instead.
@available(iOS 15, *)
@MainActor
public struct TypedNavigationShell<Root: View>: View {
    private let providedNavigator: Navigator?
    private let configuration: TopNavigationBarConfiguration
    private let destinations: NavigationDestinations
    private let rootBuilder: (Navigator) -> Root

    @StateObject private var ownedNavigator = Navigator()
    @StateObject private var routingState: _RoutingState

    /// Creates a typed navigation shell.
    ///
    /// - Parameters:
    ///   - navigator: Optional external `Navigator` instance to reuse.
    ///   - configuration: Shared top bar styling configuration for this stack.
    ///   - destinations: A bundle of destination registrations for this stack.
    ///   - root: Root screen builder.
    public init(
        navigator: Navigator? = nil,
        configuration: TopNavigationBarConfiguration = .defaultMaterial,
        destinations: NavigationDestinations,
        @ViewBuilder root: @escaping (Navigator) -> Root
    ) {
        self.providedNavigator = navigator
        self.configuration = configuration
        self.destinations = destinations
        self.rootBuilder = root

        _routingState = StateObject(
            wrappedValue: _RoutingState(destinations: destinations)
        )
    }

    /// Creates a typed navigation shell.
    ///
    /// This overload accepts a plain registration closure for convenience.
    public init(
        navigator: Navigator? = nil,
        configuration: TopNavigationBarConfiguration = .defaultMaterial,
        destinations: @escaping @MainActor (NavigationDestinationRegistering) -> Void,
        @ViewBuilder root: @escaping (Navigator) -> Root
    ) {
        self.init(
            navigator: navigator,
            configuration: configuration,
            destinations: NavigationDestinations(destinations),
            root: root
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
                routingRegistry: routingState.registry,
                root: { rootBuilder(navigator) }
            )
        }
        .ignoresSafeArea(.all, edges: .top)
    }
}

@MainActor
private final class _RoutingState: ObservableObject {
    let registry: NavigationDestinationRegistry

    init(destinations: NavigationDestinations) {
        let registry = NavigationDestinationRegistry()
        // `destinations` is expected to be deterministic (avoid side effects).
        // It configures the registry by registering all typed destinations for this stack.
        destinations.register(into: registry)
        self.registry = registry
    }
}
