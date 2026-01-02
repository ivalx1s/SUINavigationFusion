import Foundation

/// `UserDefaults`-backed store for navigation stack snapshots.
///
/// `UserDefaults` does not conform to `Sendable`, but it is designed to be used across threads.
/// This store is used from the library's `@MainActor` restoration pipeline, so `@unchecked Sendable`
/// here is a pragmatic way to keep the public protocol `Sendable` without forcing callers to re-wrap `UserDefaults`.
public struct UserDefaultsNavigationStackStore: NavigationStackStateStore, @unchecked Sendable {
    public var userDefaults: UserDefaults
    public var namespace: String

    public init(
        userDefaults: UserDefaults = .standard,
        namespace: String = "SUINavigationFusion.NavigationStack"
    ) {
        self.userDefaults = userDefaults
        self.namespace = namespace
    }

    public func load(key: String) -> Data? {
        return userDefaults.data(forKey: namespacedKey(key))
    }

    public func save(key: String, data: Data?) {
        let storageKey = namespacedKey(key)
        if let data {
            userDefaults.set(data, forKey: storageKey)
        } else {
            userDefaults.removeObject(forKey: storageKey)
        }

        // Persist immediately so state is available even if the process is terminated without
        // running normal backgrounding/cleanup hooks (for example, when stopping the app from Xcode).
        //
        // `synchronize()` is generally not needed for typical apps, but for state restoration caches
        // it provides a more predictable developer experience.
        userDefaults.synchronize()
    }

    private func namespacedKey(_ key: String) -> String {
        "\(namespace).\(key)"
    }
}
