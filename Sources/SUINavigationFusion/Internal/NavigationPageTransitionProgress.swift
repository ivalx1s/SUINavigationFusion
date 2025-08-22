import SwiftUI
import Combine

final class NavigationPageTransitionProgress: ObservableObject {
    @Published var progress: CGFloat = 0
}
