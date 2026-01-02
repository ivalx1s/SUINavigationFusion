import Foundation

/// A stable identifier for a restorable destination.
///
/// Keys are persisted as part of the navigation stack snapshot, so they should remain stable across app versions.
public struct NavigationDestinationKey: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// Convenience default for single-route wrappers.
    ///
    /// Prefer explicit keys for long-term stability.
    public static func type<T>(_ type: T.Type) -> Self {
        .init(normalizeRuntimeTypeName(String(reflecting: type)))
    }

    /// A best-effort normalization that removes unstable runtime context markers from type-based keys.
    ///
    /// Swift can include segments like `.(unknown context at $0123abcd)` in `String(reflecting:)` for certain
    /// non-top-level or private types. Those markers are not stable across process launches, which would break
    /// restoration lookups.
    ///
    /// Normalization is applied automatically by `.type(...)` and is also used during restoration lookups.
    public var normalized: Self {
        .init(Self.normalizeRuntimeTypeName(rawValue))
    }
}

private extension NavigationDestinationKey {
    static func normalizeRuntimeTypeName(_ name: String) -> String {
        var result = name
        let marker = ".(unknown context at $"

        while let start = result.range(of: marker) {
            guard let end = result[start.upperBound...].firstIndex(of: ")") else { break }
            result.removeSubrange(start.lowerBound...end)
        }

        return result
    }
}
