import Foundation

/// A serializable navigation payload that can be cached and restored.
///
/// `Navigator.push(_:)` accepts arbitrary SwiftUI views, which cannot be reliably serialized.
/// If you want navigation stack restoration, push a `NavigationRoute` instead via `navigator.push(route:)`.
public protocol NavigationRoute: Codable, Hashable, Sendable {}

/// Option 4 (type-erased, registry-driven) uses the same payload requirements as Option 3 (single route type).
public typealias NavigationPathItem = NavigationRoute

