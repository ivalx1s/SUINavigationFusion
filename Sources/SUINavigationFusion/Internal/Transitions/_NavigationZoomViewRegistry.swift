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

    private var sources: [AnyHashable: WeakBox] = [:]
    private var destinations: [AnyHashable: WeakBox] = [:]

    func setSourceView(_ view: UIView, for id: AnyHashable) {
        sources[id] = WeakBox(view)
    }

    func setDestinationView(_ view: UIView, for id: AnyHashable) {
        destinations[id] = WeakBox(view)
    }

    func sourceView(for id: AnyHashable) -> UIView? {
        if let view = sources[id]?.view { return view }
        sources[id] = nil
        return nil
    }

    func destinationView(for id: AnyHashable) -> UIView? {
        if let view = destinations[id]?.view { return view }
        destinations[id] = nil
        return nil
    }

    func clearSourceView(for id: AnyHashable, ifCurrentViewIs view: UIView?) {
        guard let current = sources[id]?.view else {
            sources[id] = nil
            return
        }
        if current === view {
            sources[id] = nil
        }
    }

    func clearDestinationView(for id: AnyHashable, ifCurrentViewIs view: UIView?) {
        guard let current = destinations[id]?.view else {
            destinations[id] = nil
            return
        }
        if current === view {
            destinations[id] = nil
        }
    }
    #endif
}

