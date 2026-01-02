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
    }

    func clear() {
        saveSnapshotData(nil)
    }

    func restoreIfAvailable(
        navigationController: NCUINavigationController,
        rootController: UIViewController,
        navigator: Navigator
    ) {
        guard let data = store.load(key: id) else { return }

        let snapshot: _NavigationStackSnapshot
        do {
            snapshot = try decoder.decode(_NavigationStackSnapshot.self, from: data)
        } catch {
            saveSnapshotData(nil)
            return
        }

        var restoredViewControllers: [UIViewController] = []
        var restoredEntries: [_NavigationStackSnapshot.Entry] = []

        for entry in snapshot.entries {
            guard let registration = registry.registration(for: entry.key) else {
                policy.onFailure(.missingDestination(key: entry.key))
                handleRestoreFailure(&restoredViewControllers, &restoredEntries)
                break
            }

            do {
                let view = try registration.buildViewFromPayload(entry.payload, decoder)
                let restorationInfo = _NavigationRestorationInfo(key: entry.key, payload: entry.payload)
                let controller = navigator._makeHostingController(
                    content: view,
                    disableBackGesture: entry.disableBackGesture,
                    restorationInfo: restorationInfo
                )
                restoredViewControllers.append(controller)
                restoredEntries.append(entry)
            } catch {
                policy.onFailure(.decodeFailed(key: entry.key, errorDescription: String(describing: error)))
                handleRestoreFailure(&restoredViewControllers, &restoredEntries)
                break
            }
        }

        if restoredViewControllers.isEmpty {
            // Either there was nothing to restore, or restoring failed immediately.
            // Keep the root-only stack and clear any invalid cached state.
            if snapshot.entries.isEmpty {
                saveSnapshotData(nil)
            } else if restoredEntries.isEmpty {
                saveSnapshotData(nil)
            } else {
                saveSnapshot(_NavigationStackSnapshot(entries: restoredEntries))
            }
            return
        }

        navigationController.setViewControllers([rootController] + restoredViewControllers, animated: false)
        saveSnapshot(_NavigationStackSnapshot(entries: restoredEntries))
    }

    func syncSnapshot(from navigationController: NCUINavigationController) {
        var entries: [_NavigationStackSnapshot.Entry] = []

        for controller in navigationController.viewControllers.dropFirst() {
            guard
                let restorable = controller as? _NavigationRestorable,
                let info = restorable._restorationInfo
            else {
                // A non-restorable controller breaks determinism for everything above it.
                break
            }

            entries.append(
                .init(
                    key: info.key,
                    payload: info.payload,
                    disableBackGesture: restorable.disablesBackGesture
                )
            )
        }

        if entries.isEmpty {
            saveSnapshotData(nil)
        } else {
            saveSnapshot(_NavigationStackSnapshot(entries: entries))
        }
    }

    private func handleRestoreFailure(
        _ restoredViewControllers: inout [UIViewController],
        _ restoredEntries: inout [_NavigationStackSnapshot.Entry]
    ) {
        switch policy.behavior {
        case .dropSuffixAndContinue:
            return
        case .clearAllAndShowRoot:
            restoredViewControllers.removeAll()
            restoredEntries.removeAll()
        }
    }

    private func saveSnapshot(_ snapshot: _NavigationStackSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
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
