import SwiftUI
import Foundation

/// A navigation shell that supports caching/restoring the navigation stack and typed route destinations (Option 4).
///
/// The stack is restored from a persisted snapshot of `{destinationKey, payload}` entries.
/// Only `navigator.push(route:)` participates in restoration; `navigator.push(_ view:)` is treated as transient.
///
/// The `id` is used as the persistence key. Use `idScope: .scene` to isolate snapshots per window/scene.
///
/// Path-driven navigation (NavigationStack-like):
/// If you pass a `path:` binding, the shell treats that path as the desired navigation state and reconciles
/// the underlying UIKit stack to match it. Interactive swipe-back updates the bound path, so an external router
/// can own navigation state in the same way as SwiftUI’s `NavigationStack(path:)`.
///
/// In path-driven mode the stack must remain route-backed (representable as `SUINavigationPath` elements).
/// `Navigator.push(_ view:)` is therefore not supported and will assert + no-op.
@MainActor
public struct PathRestorableNavigationShell<Root: View>: View {
    private let id: String
    private let idScope: NavigationStackIDScope
    private let path: Binding<SUINavigationPath>?
    private let providedNavigator: Navigator?
    private let configuration: TopNavigationBarConfiguration
    private let store: NavigationStackStateStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let policy: NavigationRestorePolicy
    private let destinations: NavigationDestinations
    private let rootBuilder: (Navigator) -> Root

    /// A stable per-scene identifier used when `idScope == .scene`.
    ///
    /// This allows multiple windows/scenes to use the same base `id` without overwriting each other’s snapshots.
    @SceneStorage("SUINavigationFusion.NavigationStack.sceneID") private var sceneID = UUID().uuidString

    /// Creates a restorable navigation shell (Option 4 – registry-driven).
    ///
    /// - Parameters:
    ///   - id: Base persistence identifier for this navigation stack.
    ///   - idScope: Controls whether `id` is global (`.global`) or scoped per scene/window (`.scene`).
    ///   - path: Optional bound navigation path. When provided, enables path-driven navigation.
    ///   - navigator: Optional external `Navigator` instance to reuse.
    ///   - configuration: Shared top bar styling configuration for this stack.
    ///   - store: Storage backend for persisted navigation snapshots.
    ///   - encoder: Encoder used to serialize route payloads and snapshots.
    ///   - decoder: Decoder used to deserialize route payloads and snapshots.
    ///   - policy: Failure policy for missing destinations or decode failures.
    ///   - destinations: A composable bundle of destination registrations for this stack.
    ///     The bundle is applied once when the shell’s restoration state is created and is expected to be deterministic
    ///     (avoid side effects). It ultimately registers destinations by mutating a registry via `registry.register(...)`.
    ///   - root: Root screen builder (not persisted).
    public init(
        id: String,
        idScope: NavigationStackIDScope = .global,
        path: Binding<SUINavigationPath>? = nil,
        navigator: Navigator? = nil,
        configuration: TopNavigationBarConfiguration = .defaultMaterial,
        store: NavigationStackStateStore = UserDefaultsNavigationStackStore(),
        encoder: JSONEncoder = .init(),
        decoder: JSONDecoder = .init(),
        policy: NavigationRestorePolicy = .init(),
        destinations: NavigationDestinations,
        @ViewBuilder root: @escaping (Navigator) -> Root
    ) {
        self.id = id
        self.idScope = idScope
        self.path = path
        self.providedNavigator = navigator
        self.configuration = configuration
        self.store = store
        self.encoder = encoder
        self.decoder = decoder
        self.policy = policy
        self.destinations = destinations
        self.rootBuilder = root
    }

    /// Creates a restorable navigation shell (Option 4 – registry-driven).
    ///
    /// This overload accepts a plain registration closure for convenience.
    public init(
        id: String,
        idScope: NavigationStackIDScope = .global,
        path: Binding<SUINavigationPath>? = nil,
        navigator: Navigator? = nil,
        configuration: TopNavigationBarConfiguration = .defaultMaterial,
        store: NavigationStackStateStore = UserDefaultsNavigationStackStore(),
        encoder: JSONEncoder = .init(),
        decoder: JSONDecoder = .init(),
        policy: NavigationRestorePolicy = .init(),
        destinations: @escaping @MainActor (NavigationDestinationRegistering) -> Void,
        @ViewBuilder root: @escaping (Navigator) -> Root
    ) {
        self.init(
            id: id,
            idScope: idScope,
            path: path,
            navigator: navigator,
            configuration: configuration,
            store: store,
            encoder: encoder,
            decoder: decoder,
            policy: policy,
            destinations: NavigationDestinations(destinations),
            root: root
        )
    }

    /// Final persistence identifier derived from `id` and `idScope`.
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
            path: path,
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
/// Core implementation that owns `@StateObject` state for restoration.
///
/// The outer shell computes `effectiveID` (including `@SceneStorage` when needed) and passes it here.
/// This avoids initializing `@StateObject` with an id that may not yet be available during `init`.
private struct _PathRestorableNavigationShellCore<Root: View>: View {
    private let id: String
    private let path: Binding<SUINavigationPath>?
    private let providedNavigator: Navigator?
    private let configuration: TopNavigationBarConfiguration
    private let rootBuilder: (Navigator) -> Root

    @StateObject private var ownedNavigator = Navigator()
    @StateObject private var restorationState: _RestorationState

    init(
        id: String,
        path: Binding<SUINavigationPath>?,
        navigator: Navigator?,
        configuration: TopNavigationBarConfiguration,
        store: NavigationStackStateStore,
        encoder: JSONEncoder,
        decoder: JSONDecoder,
        policy: NavigationRestorePolicy,
        destinations: NavigationDestinations,
        @ViewBuilder root: @escaping (Navigator) -> Root
    ) {
        self.id = id
        self.path = path
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
        let pathDriver: _NavigationPathDriver? = path.map { binding in
            _NavigationPathDriver(
                get: { binding.wrappedValue },
                set: { newPath, _ in binding.wrappedValue = newPath },
                encoder: restorationState.context.encoder
            )
        }

        VStack {
            _NavigationRoot(
                navigator: navigator,
                configuration: configuration,
                restorationContext: restorationState.context,
                pathDriver: pathDriver,
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
        destinations: NavigationDestinations
    ) {
        let registry = NavigationDestinationRegistry()
        // `destinations` is intentionally a configuration bundle: it registers destinations by mutating `registry`
        // via `registry.register(...)` and is applied once when this state is created. The configured registry is then
        // used to build views for both `navigator.push(route:)` and restore-time reconstruction.
        destinations.register(into: registry)

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
