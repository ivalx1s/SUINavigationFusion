import SwiftUI

@MainActor
final class TopNavigationBarConfigurationStore: ObservableObject {
    @Published var configuration: TopNavigationBarConfiguration

    init(configuration: TopNavigationBarConfiguration = .defaultMaterial) {
        self.configuration = configuration
    }
}

