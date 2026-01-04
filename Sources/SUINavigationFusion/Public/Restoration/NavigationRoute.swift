import Foundation

/// A serializable navigation payload that can be cached and restored.
///
/// `Navigator.push(_:)` accepts arbitrary SwiftUI views, which cannot be reliably serialized.
/// If you want navigation stack restoration, push a `NavigationRoute` instead via `navigator.push(route:)`.
public protocol NavigationRoute: Codable, Hashable, Sendable {}

/// A route payload that can be used to build a `SUINavigationPath` without consulting a destination registry.
///
/// In path-driven mode (NavigationStack-like), external routers may need to construct a heterogeneous navigation path
/// without having direct access to the stack’s destination registry. `NavigationPathItem` provides a stable
/// `destinationKey` for this purpose.
///
/// - Important: Prefer explicit, namespaced keys for shipped apps. The default `.type(Self.self)` is convenient but
///   refactor-sensitive.
public protocol NavigationPathItem: NavigationRoute {
    /// A stable destination key for this route payload type.
    ///
    /// The key is persisted in `SUINavigationPath` and must match the key used when registering destinations.
    static var destinationKey: NavigationDestinationKey { get }
}

public extension NavigationPathItem {
    static var destinationKey: NavigationDestinationKey { .type(Self.self) }
}
