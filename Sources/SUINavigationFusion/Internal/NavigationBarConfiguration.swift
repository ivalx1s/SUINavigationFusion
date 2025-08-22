import SwiftUI


// MARK: – Environment support for NavigationBarConfiguration
private struct NavigationBarConfigurationKey: EnvironmentKey {
    static let defaultValue: TopNavigationBarConfiguration = .defaultMaterial
}

extension EnvironmentValues {
    var topNavigationBarConfiguration: TopNavigationBarConfiguration {
        get { self[NavigationBarConfigurationKey.self] }
        set { self[NavigationBarConfigurationKey.self] = newValue }
    }
}

extension View {
    func topNavigationBarConfiguration(_ configuration: TopNavigationBarConfiguration) -> some View {
        environment(\.topNavigationBarConfiguration, configuration)
    }
}
