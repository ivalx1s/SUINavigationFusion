import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
/// Stores UIKit views used as anchors for iOS 18+ native zoom transitions.
///
/// UIKit zoom transitions require real `UIView` instances as animation sources/targets.
/// SwiftUI code provides those views by attaching `.suinavZoomSource(id:)` and `.suinavZoomDestination(id:)`,
/// which bridge into UIKit via `UIViewRepresentable` and register the underlying container view here.
///
/// - Important:
///   The transition system must never capture a concrete `UIView` for the entire lifetime of a transition.
///   UIKit asks for the source view both when pushing and when popping, so we store only an id → weak view mapping
///   and resolve the view on demand.
final class _NavigationZoomViewRegistry {
    #if canImport(UIKit)
    private final class WeakBox {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }

    // SwiftUI view hierarchies can re-create backing UIViews frequently. A single “id → view” mapping can end up
    // pointing at a stale-but-alive view that is no longer inside the active navigation controller.
    //
    // To make zoom transitions robust, store *multiple* weak candidates per id and resolve the “best” match
    // at transition time using UIKit’s `UIZoomTransitionSourceViewProviderContext` (which provides the
    // `sourceViewController`).
    private var sources: [AnyHashable: [WeakBox]] = [:]
    private var destinations: [AnyHashable: [WeakBox]] = [:]

    func setSourceView(_ view: UIView, for id: AnyHashable) {
        sources[id] = updatedList(appending: view, to: sources[id])
    }

    func setDestinationView(_ view: UIView, for id: AnyHashable) {
        destinations[id] = updatedList(appending: view, to: destinations[id])
    }

    func sourceView(for id: AnyHashable) -> UIView? {
        // Legacy fallback: return any alive view (preferring the most recently registered one).
        // For transitions, prefer `sourceView(for:inHierarchyOf:)`.
        guard var list = sources[id] else { return nil }
        list.removeAll { $0.view == nil }
        sources[id] = list.isEmpty ? nil : list
        return list.last?.view
    }

    func destinationView(for id: AnyHashable) -> UIView? {
        // Legacy fallback: return any alive view (preferring the most recently registered one).
        // For transitions, prefer `destinationView(for:inHierarchyOf:)`.
        guard var list = destinations[id] else { return nil }
        list.removeAll { $0.view == nil }
        destinations[id] = list.isEmpty ? nil : list
        return list.last?.view
    }

    /// Returns the best matching zoom source view for the given id inside a specific view hierarchy.
    ///
    /// UIKit’s zoom source provider context includes a `sourceViewController`. If we return a view that does not
    /// belong to that controller, UIKit may fall back to a degraded animation (often perceived as a fade).
    func sourceView(for id: AnyHashable, inHierarchyOf rootView: UIView) -> UIView? {
        bestView(from: &sources, id: id, inHierarchyOf: rootView)
    }

    /// Returns the best matching zoom destination view for the given id inside a specific view hierarchy.
    func destinationView(for id: AnyHashable, inHierarchyOf rootView: UIView) -> UIView? {
        bestView(from: &destinations, id: id, inHierarchyOf: rootView)
    }

    /// Returns all matching zoom source views for the given id inside a specific view hierarchy.
    ///
    /// Useful for temporarily hiding all duplicates during a zoom transition (SwiftUI can briefly produce multiple
    /// backing views for the same anchor id).
    func sourceViews(for id: AnyHashable, inHierarchyOf rootView: UIView) -> [UIView] {
        allViews(from: &sources, id: id, inHierarchyOf: rootView)
    }

    /// Returns all matching zoom destination views for the given id inside a specific view hierarchy.
    func destinationViews(for id: AnyHashable, inHierarchyOf rootView: UIView) -> [UIView] {
        allViews(from: &destinations, id: id, inHierarchyOf: rootView)
    }

    func clearSourceView(for id: AnyHashable, ifCurrentViewIs view: UIView?) {
        guard let view else {
            sources[id] = nil
            return
        }
        sources[id] = removing(view: view, from: sources[id])
    }

    func clearDestinationView(for id: AnyHashable, ifCurrentViewIs view: UIView?) {
        guard let view else {
            destinations[id] = nil
            return
        }
        destinations[id] = removing(view: view, from: destinations[id])
    }

    // MARK: - Helpers

    private func updatedList(appending view: UIView, to existing: [WeakBox]?) -> [WeakBox] {
        var list = existing ?? []
        // Drop dead and duplicate references.
        list.removeAll { box in
            guard let current = box.view else { return true }
            return current === view
        }
        list.append(WeakBox(view))
        return list
    }

    private func removing(view: UIView, from existing: [WeakBox]?) -> [WeakBox]? {
        guard var list = existing else { return nil }
        list.removeAll { box in
            guard let current = box.view else { return true }
            return current === view
        }
        return list.isEmpty ? nil : list
    }

    private func bestView(
        from storage: inout [AnyHashable: [WeakBox]],
        id: AnyHashable,
        inHierarchyOf rootView: UIView
    ) -> UIView? {
        guard var list = storage[id] else { return nil }
        // Prefer the most recently registered view, but only if it’s actually inside the required hierarchy.
        for box in list.reversed() {
            guard let view = box.view else { continue }
            guard view.window != nil else { continue }
            guard view.isDescendant(of: rootView) else { continue }
            return view
        }
        // Cleanup dead entries.
        list.removeAll { $0.view == nil }
        storage[id] = list.isEmpty ? nil : list
        return nil
    }

    private func allViews(
        from storage: inout [AnyHashable: [WeakBox]],
        id: AnyHashable,
        inHierarchyOf rootView: UIView
    ) -> [UIView] {
        guard var list = storage[id] else { return [] }
        var result: [UIView] = []
        for box in list {
            guard let view = box.view else { continue }
            guard view.isDescendant(of: rootView) else { continue }
            result.append(view)
        }
        // Cleanup dead entries.
        list.removeAll { $0.view == nil }
        storage[id] = list.isEmpty ? nil : list
        return result
    }
    #endif
}
