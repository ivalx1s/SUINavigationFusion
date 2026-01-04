import Foundation

/// A type-erased, codable navigation path (NavigationStack-like).
///
/// This is the canonical representation of a route-backed navigation stack in SUINavigationFusion:
/// - external routers can own and mutate it
/// - restorable shells persist/restore it
/// - the UIKit stack is reconciled to match it in path-driven mode
///
/// Each element stores `{destinationKey, payload}` where:
/// - `destinationKey` identifies the destination (registered in `NavigationDestinationRegistry`)
/// - `payload` is the encoded `NavigationRoute` value (typically via `JSONEncoder`)
///
/// `schemaVersion` is persisted to allow future format evolution.
public struct SUINavigationPath: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var elements: [Element]

    /// Creates a navigation path.
    ///
    /// - Parameters:
    ///   - schemaVersion: Persisted format version (default: `1`).
    ///   - elements: Initial elements (default: `[]`).
    public init(schemaVersion: Int = 1, elements: [Element] = []) {
        self.schemaVersion = schemaVersion
        self.elements = elements
    }

    /// A single element in the navigation path.
    public struct Element: Codable, Hashable, Sendable {
        public var key: NavigationDestinationKey
        public var payload: Data
        public var disableBackGesture: Bool

        public init(
            key: NavigationDestinationKey,
            payload: Data,
            disableBackGesture: Bool = false
        ) {
            self.key = key
            self.payload = payload
            self.disableBackGesture = disableBackGesture
        }
    }

    // Keep on-disk compatibility with the previous internal snapshot shape (`schemaVersion` + `entries`).
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case elements = "entries"
    }
}

public extension SUINavigationPath {
    /// Removes all elements from the path.
    mutating func clear() {
        elements.removeAll()
    }

    /// Removes the last `k` elements from the path.
    ///
    /// If `k` exceeds the current element count, the path becomes empty.
    mutating func removeLast(_ k: Int = 1) {
        guard k > 0 else { return }
        if k >= elements.count {
            elements.removeAll()
        } else {
            elements.removeLast(k)
        }
    }

    /// Appends a pre-encoded element.
    mutating func append(_ element: Element) {
        elements.append(element)
    }

    /// Encodes and appends a route payload under an explicit destination key.
    ///
    /// Use this overload when your router does not rely on `NavigationPathItem.destinationKey`.
    mutating func append<Route: NavigationRoute>(
        route: Route,
        key: NavigationDestinationKey,
        encoder: JSONEncoder = .init(),
        disableBackGesture: Bool = false
    ) throws {
        let payload = try encoder.encode(route)
        elements.append(.init(key: key, payload: payload, disableBackGesture: disableBackGesture))
    }

    /// Encodes and appends a route payload using `Route.destinationKey`.
    mutating func append<Route: NavigationPathItem>(
        route: Route,
        encoder: JSONEncoder = .init(),
        disableBackGesture: Bool = false
    ) throws {
        try append(route: route, key: Route.destinationKey, encoder: encoder, disableBackGesture: disableBackGesture)
    }
}

