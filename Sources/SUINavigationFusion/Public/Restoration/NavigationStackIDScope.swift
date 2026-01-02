import Foundation

/// Defines how a restorable navigation stack `id` is scoped.
///
/// The `id` is used as the persistence key for navigation stack snapshots.
public enum NavigationStackIDScope: Sendable {
    /// A single shared stack per `id` (default).
    case global

    /// A separate stack per scene/window per `id`.
    ///
    /// This prevents multiple windows from overwriting each other’s snapshots when they use the same base `id`.
    /// The library derives a stable per-scene identifier using `@SceneStorage` and combines it with the base `id`.
    case scene
}

