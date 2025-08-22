import SwiftUI

public struct NavigationShell<Root: View>: View {
    private let navigator: Navigator?
    private let rootBuilder: (Navigator) -> Root
    private let configuration: TopNavigationBarConfiguration

    public init(
        configuration: TopNavigationBarConfiguration = .defaultMaterial,
        @ViewBuilder root: @escaping (Navigator) -> Root
    ) {
        self.navigator = nil
        self.rootBuilder = root
        self.configuration = configuration
    }

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
