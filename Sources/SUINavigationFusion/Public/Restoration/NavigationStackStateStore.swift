import Foundation

/// Storage backend for persisted navigation stack snapshots.
///
/// A store is intentionally simple: it reads and writes opaque `Data?` by a caller-provided key.
public protocol NavigationStackStateStore: Sendable {
    func load(key: String) -> Data?
    func save(key: String, data: Data?)
}

