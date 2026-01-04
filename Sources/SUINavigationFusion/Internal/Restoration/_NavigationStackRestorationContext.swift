import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
/// Internal engine that persists and restores a route-backed navigation stack.
///
/// The persisted representation is `SUINavigationPath`:
/// - each element stores `{destinationKey, payload, disableBackGesture}`
/// - the registry maps keys back to concrete payload types and view builders
///
/// This type is used in two modes:
/// - **imperative stacks**: `Navigator` pushes/pops UIKit controllers directly and the context keeps a snapshot in sync
/// - **path-driven stacks**: `_NavigationRoot` reconciles UIKit to a bound `SUINavigationPath`, and the context provides
///   the “decode → build controllers” primitive (plus policy-based sanitization)
final class _NavigationStackRestorationContext {
    private let id: String
    private let store: NavigationStackStateStore
    let registry: NavigationDestinationRegistry
    let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let policy: NavigationRestorePolicy

    private var lastSavedData: Data?

    init(
        id: String,
        store: NavigationStackStateStore,
        registry: NavigationDestinationRegistry,
        encoder: JSONEncoder,
        decoder: JSONDecoder,
        policy: NavigationRestorePolicy
    ) {
        self.id = id
        self.store = store
        self.registry = registry
        self.encoder = encoder
        self.decoder = decoder
        self.policy = policy
        // Seed with persisted value so `saveSnapshotData(nil)` actually clears stale/corrupt data.
        self.lastSavedData = store.load(key: id)
    }

    /// Clears the persisted snapshot for this stack id.
    func clear() {
        // Clear unconditionally (do not rely on `lastSavedData` to reflect external store changes).
        lastSavedData = nil
        store.save(key: id, data: nil)
    }

    func restoreIfAvailable(
        navigationController: NCUINavigationController,
        rootController: UIViewController,
        navigator: Navigator
    ) {
        guard let data = store.load(key: id) else {
            lastSavedData = nil
            return
        }
        lastSavedData = data

        let storedPath: SUINavigationPath
        do {
            storedPath = try decoder.decode(SUINavigationPath.self, from: data)
        } catch {
            saveSnapshotData(nil)
            return
        }

        guard storedPath.schemaVersion == 1 else {
            saveSnapshotData(nil)
            return
        }

        let (restoredViewControllers, restoredPath) = buildViewControllers(for: storedPath, navigator: navigator)

        guard !restoredViewControllers.isEmpty else {
            // Either there was nothing to restore, or restoring failed immediately.
            // Keep the root-only stack and clear any invalid cached state.
            saveSnapshotData(nil)
            return
        }

        navigationController.setViewControllers([rootController] + restoredViewControllers, animated: false)
        savePath(restoredPath)
    }

    /// Persists a snapshot derived from the current UIKit stack.
    ///
    /// - Important: scanning stops at the first non-restorable controller above root.
    ///   A transient `push(_ view:)` breaks determinism for everything above it.
    ///
    /// - Returns: The derived path and whether the entire suffix above root was representable.
    @discardableResult
    func syncSnapshot(from navigationController: NCUINavigationController) -> (path: SUINavigationPath, isFullyRepresentable: Bool) {
        let (path, isFullyRepresentable) = currentPath(from: navigationController)

        if path.elements.isEmpty {
            saveSnapshotData(nil)
        } else {
            savePath(path)
        }

        return (path, isFullyRepresentable)
    }

    /// Builds hosting controllers for the given desired path.
    ///
    /// The result is policy-sanitized:
    /// - `.dropSuffixAndContinue`: returns the successfully built prefix and drops the invalid suffix
    /// - `.clearAllAndShowRoot`: returns an empty array + empty path
    ///
    /// - Returns:
    ///   - `viewControllers`: controllers for the restored/sanitized prefix
    ///   - `sanitizedPath`: the path prefix that was actually representable
    func buildViewControllers(
        for path: SUINavigationPath,
        navigator: Navigator
    ) -> (viewControllers: [UIViewController], sanitizedPath: SUINavigationPath) {
        guard path.schemaVersion == 1 else {
            return ([], SUINavigationPath())
        }

        var viewControllers: [UIViewController] = []
        var elements: [SUINavigationPath.Element] = []

        for element in path.elements {
            guard let (controller, _) = buildViewController(for: element, navigator: navigator) else {
                if policy.behavior == .clearAllAndShowRoot {
                    return ([], SUINavigationPath())
                }
                break
            }

            viewControllers.append(controller)
            elements.append(element)
        }

        return (viewControllers, SUINavigationPath(elements: elements))
    }

    /// Builds a single hosting controller for a path element and returns its default transition (if any).
    ///
    /// This helper is used both for full-stack restoration and for path-driven “push one element” updates,
    /// so the decode/build logic stays centralized.
    func buildViewController(
        for element: SUINavigationPath.Element,
        navigator: Navigator
    ) -> (viewController: UIViewController, defaultTransition: SUINavigationTransition?)? {
        guard let registration = registry.registration(for: element.key) else {
            policy.onFailure(.missingDestination(key: element.key))
            return nil
        }

        do {
            let value = try registration.decodeValue(element.payload, decoder)
            let view = registration.buildViewFromValue(value)
            let defaultTransition = registration.defaultTransitionFromValue?(value)
            let restorationInfo = _NavigationRestorationInfo(key: element.key, payload: element.payload)
            let controller = navigator._makeHostingController(
                content: view,
                disableBackGesture: element.disableBackGesture,
                restorationInfo: restorationInfo
            )
            return (controller, defaultTransition)
        } catch {
            policy.onFailure(.decodeFailed(key: element.key, errorDescription: String(describing: error)))
            return nil
        }
    }

    /// Derives the current `SUINavigationPath` from the UIKit stack.
    ///
    /// - Returns:
    ///   - `path`: representable prefix above root
    ///   - `isFullyRepresentable`: `false` if a non-restorable controller was found above root
    func currentPath(from navigationController: NCUINavigationController) -> (path: SUINavigationPath, isFullyRepresentable: Bool) {
        var elements: [SUINavigationPath.Element] = []

        for controller in navigationController.viewControllers.dropFirst() {
            guard
                let restorable = controller as? _NavigationRestorable,
                let info = restorable._restorationInfo
            else {
                // A non-restorable controller breaks determinism for everything above it.
                break
            }

            elements.append(
                .init(
                    key: info.key,
                    payload: info.payload,
                    disableBackGesture: restorable.disablesBackGesture
                )
            )
        }

        let isFullyRepresentable = (elements.count == navigationController.viewControllers.dropFirst().count)
        return (SUINavigationPath(elements: elements), isFullyRepresentable)
    }

    private func savePath(_ path: SUINavigationPath) {
        do {
            let data = try encoder.encode(path)
            saveSnapshotData(data)
        } catch {
            saveSnapshotData(nil)
        }
    }

    private func saveSnapshotData(_ data: Data?) {
        guard data != lastSavedData else { return }
        lastSavedData = data
        store.save(key: id, data: data)
    }
}
