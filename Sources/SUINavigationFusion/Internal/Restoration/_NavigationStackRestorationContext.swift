import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
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
            guard let registration = registry.registration(for: element.key) else {
                policy.onFailure(.missingDestination(key: element.key))
                if policy.behavior == .clearAllAndShowRoot {
                    return ([], SUINavigationPath())
                }
                break
            }

            do {
                let view = try registration.buildViewFromPayload(element.payload, decoder)
                let restorationInfo = _NavigationRestorationInfo(key: element.key, payload: element.payload)
                let controller = navigator._makeHostingController(
                    content: view,
                    disableBackGesture: element.disableBackGesture,
                    restorationInfo: restorationInfo
                )
                viewControllers.append(controller)
                elements.append(element)
            } catch {
                policy.onFailure(.decodeFailed(key: element.key, errorDescription: String(describing: error)))
                if policy.behavior == .clearAllAndShowRoot {
                    return ([], SUINavigationPath())
                }
                break
            }
        }

        return (viewControllers, SUINavigationPath(elements: elements))
    }

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
