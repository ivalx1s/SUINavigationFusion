import SwiftUI

/// A SwiftUI container that hosts your screens inside a UIKit `UINavigationController`,
/// hides the system `UINavigationBar`, and renders a custom SwiftUI top bar instead.
///
/// `NavigationShell` is the simplest entry point:
/// - it creates (or reuses) a `Navigator`
/// - injects it as an `EnvironmentObject` into every hosted screen
/// - applies a shared `TopNavigationBarConfiguration` to the whole stack
///
/// Use `Navigator` for imperative navigation (`push` / `pop` / ...).
///
/// If you need typed route pushes (`navigator.push(route:)`) use `TypedNavigationShell`.
/// If you need persistence / state restoration or external router-driven navigation path, use
/// `PathRestorableNavigationShell` / `RestorableNavigationShell`.
@MainActor
public struct NavigationShell<Root: View>: View {
    private let navigator: Navigator?
    private let rootBuilder: (Navigator) -> Root
    private let configuration: TopNavigationBarConfiguration

    /// Creates a navigation shell that owns its `Navigator` instance.
    ///
    /// - Parameters:
    ///   - configuration: Styling for the custom top bar and stack-wide tint behavior.
    ///   - root: Root screen builder. The created `Navigator` is passed in as an argument.
    public init(
        configuration: TopNavigationBarConfiguration = .defaultMaterial,
        @ViewBuilder root: @escaping (Navigator) -> Root
    ) {
        self.navigator = nil
        self.rootBuilder = root
        self.configuration = configuration
    }

    /// Creates a navigation shell that reuses an externally managed `Navigator`.
    ///
    /// This is useful when you need to keep a stable navigator instance outside the view tree
    /// (for example, to integrate with a coordinator/router object).
    ///
    /// - Parameters:
    ///   - navigator: External `Navigator` instance.
    ///   - configuration: Styling for the custom top bar and stack-wide tint behavior.
    ///   - root: Root screen builder.
    public init(
        navigator: Navigator,
        configuration: TopNavigationBarConfiguration = .defaultMaterial,
        @ViewBuilder root: @escaping () -> Root
    ) {
        self.navigator = navigator
        self.rootBuilder = { navigator in root() }
        self.configuration = configuration
    }

    // MARK: – Body

    public var body: some View {
        VStack {
            if let nav = navigator {
                _NavigationRoot(navigator: nav, configuration: configuration, root: { rootBuilder(nav) })
            } else {
                _NavigationRoot(configuration: configuration, root: rootBuilder)
            }
        }
        .ignoresSafeArea(.all, edges: .top)
    }
}
